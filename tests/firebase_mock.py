#!/usr/bin/env python3
"""Finto Firebase (Realtime Database REST + accesso anonimo) per provare il gioco online in locale.

Uso:  python3 tests/firebase_mock.py 8765 [file delle regole]
Poi avviare Godot con
  MK_DB_URL=http://127.0.0.1:8765/db
  MK_AUTH_URL=http://127.0.0.1:8765/signup
  MK_REFRESH_URL=http://127.0.0.1:8765/refresh
(nella versione web: pagina?mkdb=http://127.0.0.1:8765/db)

A differenza dei finti Firebase di Kingsburg/BEAST, questo APPLICA DAVVERO le regole di
firebase/database.rules.json (tutto il file, quindi anche le sezioni degli altri giochi): interpreta
le espressioni (.read/.write/.validate) con data/newData/root/auth/now/$variabili, come Firebase:
- lettura: permessa se un .read lungo il percorso (dalla radice in giù) è vero;
- scrittura: permessa se un .write lungo il percorso è vero (valutato con data/newData di quel livello);
  poi tutte le .validate dei nodi scritti (antenati compresi, figli nuovi compresi) devono essere vere;
- PATCH a più percorsi: tutto o niente, newData = albero dopo l'intero aggiornamento.

Opzioni (variabili d'ambiente):
  MOCK_FLAKY=0.05   una richiesta al database su 20 fallisce con 503 (prima di essere applicata)
  MOCK_LOG=1        stampa ogni richiesta rifiutata
"""
import copy
import gzip
import json
import os
import random
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

TREE = {}
TOKENS = {}
LOCK = threading.Lock()
COUNT = [0]
RULES = {}
FLAKY = float(os.environ.get("MOCK_FLAKY", "0") or 0)
LOG = os.environ.get("MOCK_LOG", "") != ""
STATS = {"get": 0, "put": 0, "patch": 0, "delete": 0, "denied": 0, "flaky": 0}


# ---------------------------------------------------------------- valori in stile JavaScript

def js_str(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    if v is None:
        return "null"
    return str(v)


class S(str):
    """Stringa delle regole: .length, .matches(/re/), concatenazione con numeri come in JS."""

    @property
    def length(self):
        return len(self)

    def matches(self, rx):
        return re.search(rx, self) is not None

    def beginsWith(self, x):
        return self.startswith(x)

    def endsWith(self, x):
        return self.endswith(x)

    def contains(self, x):
        return x in self

    def __add__(self, o):
        return S(str(self) + js_str(o))

    def __radd__(self, o):
        return S(js_str(o) + str(self))


def wrap(v):
    return S(v) if isinstance(v, str) else v


def get_at(tree, path):
    node = tree
    for p in path:
        if not isinstance(node, dict) or p not in node:
            return None
        node = node[p]
    return node


class Snap:
    def __init__(self, tree, path):
        self.tree = tree
        self.path = list(path)

    def _v(self):
        return get_at(self.tree, self.path)

    def child(self, p):
        return Snap(self.tree, self.path + [x for x in str(p).split("/") if x])

    def parent(self):
        return Snap(self.tree, self.path[:-1])

    def val(self):
        v = self._v()
        return wrap(v) if not isinstance(v, dict) else v

    def exists(self):
        return self._v() is not None

    def hasChild(self, k):
        return self.child(k).exists()

    def hasChildren(self, ks=None):
        v = self._v()
        if not isinstance(v, dict):
            return False
        return all(k in v for k in ks) if ks is not None else len(v) > 0

    def isString(self):
        return isinstance(self._v(), str)

    def isNumber(self):
        v = self._v()
        return isinstance(v, (int, float)) and not isinstance(v, bool)

    def isBoolean(self):
        return isinstance(self._v(), bool)


class Auth:
    def __init__(self, uid):
        self.uid = S(uid)


# ---------------------------------------------------------------- traduzione delle espressioni

_TOK = re.compile(r"""\s*(?:
    (?P<str>'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")
  | (?P<rx>/(?:[^/\\]|\\.)+/[a-z]*)
  | (?P<num>\d+(?:\.\d+)?)
  | (?P<var>\$[A-Za-z_]\w*)
  | (?P<id>[A-Za-z_]\w*)
  | (?P<op>===|!==|==|!=|<=|>=|&&|\|\||[!<>+\-*/%().,\[\]])
)""", re.X)

_CACHE = {}


def translate(expr):
    if expr in _CACHE:
        return _CACHE[expr]
    out = []
    pos = 0
    prev = None
    while pos < len(expr):
        m = _TOK.match(expr, pos)
        if not m or m.end() == pos:
            if expr[pos:].strip() == "":
                break
            raise ValueError("regola non interpretabile: %r @%d" % (expr, pos))
        pos = m.end()
        k = m.lastgroup
        t = m.group(k)
        if k == "rx" and prev not in ("(", ","):
            # non era una regex ma una divisione
            out.append("/")
            pos = m.start("rx") + 1
            prev = "/"
            continue
        if k == "str":
            out.append("S(%s)" % repr(t[1:-1]))
        elif k == "rx":
            body = t[1:t.rindex("/")]
            out.append(repr(body.replace("\\/", "/")))
        elif k == "num":
            out.append(t)
        elif k == "var":
            out.append("V[%r]" % t)
        elif k == "id":
            out.append({"null": "None", "true": "True", "false": "False"}.get(t, t))
        else:
            out.append({"===": "==", "!==": "!=", "&&": " and ", "||": " or ", "!": " not "}.get(t, t))
        prev = t
    code = compile(" ".join(out).strip(), "<regola>", "eval")
    _CACHE[expr] = code
    return code


def ev(expr, env):
    if isinstance(expr, bool):
        return expr
    try:
        return bool(eval(translate(expr), {"S": S}, env))
    except Exception as e:  # come Firebase: un errore di valutazione vale "falso"
        if LOG:
            print("errore nella regola", expr, e)
        return False


# ---------------------------------------------------------------- regole

def rule_children(node, key):
    """(nodo di regole del figlio, (nome variabile, valore) o None)."""
    if not isinstance(node, dict):
        return None, None
    if key in node:
        return node[key], None
    for k, v in node.items():
        if k.startswith("$"):
            return v, (k, key)
    return None, None


def rules_along(path):
    """Elenco [(profondità, nodo di regole, variabili)] dalla radice fino al percorso (dove esistono)."""
    out = []
    node = RULES.get("rules", {})
    vars_ = {}
    out.append((0, node, dict(vars_)))
    for i, p in enumerate(path):
        node, bind = rule_children(node, p)
        if node is None:
            break
        if bind:
            vars_[bind[0]] = S(bind[1])
        out.append((i + 1, node, dict(vars_)))
    return out


def env_for(uid, old, new, path, vars_):
    return {"auth": Auth(uid) if uid else None, "now": int(time.time() * 1000),
            "root": Snap(old, []), "data": Snap(old, path), "newData": Snap(new, path), "V": vars_}


def can_read(uid, path):
    for d, node, vars_ in rules_along(path):
        if ".read" in node and ev(node[".read"], env_for(uid, TREE, TREE, path[:d], vars_)):
            return True
    return False


def _validate_subtree(uid, old, new, path, node, vars_):
    """.validate del nodo e dei suoi discendenti presenti nei dati nuovi."""
    newv = get_at(new, path)
    if newv is None:
        return True
    if ".validate" in node and not ev(node[".validate"], env_for(uid, old, new, path, vars_)):
        if LOG:
            print("  validate fallita", "/".join(path), node[".validate"])
        return False
    if isinstance(newv, dict):
        for k in newv:
            ch, bind = rule_children(node, k)
            if ch is None:
                continue
            v2 = dict(vars_)
            if bind:
                v2[bind[0]] = S(bind[1])
            if not _validate_subtree(uid, old, new, path + [k], ch, v2):
                return False
    return True


def can_write(uid, path, old, new):
    along = rules_along(path)
    granted = False
    for d, node, vars_ in along:
        if ".write" in node and ev(node[".write"], env_for(uid, old, new, path[:d], vars_)):
            granted = True
            break
    if not granted:
        return False
    # .validate degli antenati (se il nodo esiste nei dati nuovi)
    for d, node, vars_ in along:
        if d < len(path) and ".validate" in node and get_at(new, path[:d]) is not None:
            if not ev(node[".validate"], env_for(uid, old, new, path[:d], vars_)):
                if LOG:
                    print("  validate (antenato) fallita", "/".join(path[:d]))
                return False
    if len(along) == len(path) + 1:
        d, node, vars_ = along[-1]
        return _validate_subtree(uid, old, new, path, node, vars_)
    return True


# ---------------------------------------------------------------- albero

def resolve(value):
    if isinstance(value, dict):
        if value.get(".sv") == "timestamp":
            return int(time.time() * 1000)
        return {k: resolve(v) for k, v in value.items()}
    return value


def set_in(tree, path, value):
    node = tree
    for p in path[:-1]:
        if not isinstance(node.get(p), dict):
            node[p] = {}
        node = node[p]
    if value is None or value == {}:
        node.pop(path[-1], None)
    else:
        node[path[-1]] = value
    prune(tree, path[:-1])


def prune(tree, path):
    """Come Firebase: i nodi rimasti vuoti spariscono."""
    for i in range(len(path), 0, -1):
        n = get_at(tree, path[:i])
        if isinstance(n, dict) and not n:
            get_at(tree, path[:i - 1]).pop(path[i - 1], None)


def firebase_json(v):
    """Come Firebase: oggetti con chiavi numeriche dense diventano array."""
    if isinstance(v, dict):
        conv = {k: firebase_json(x) for k, x in v.items()}
        if conv and all(k.isdigit() for k in conv):
            mx = max(int(k) for k in conv)
            if len(conv) * 2 > mx + 1:
                return [conv.get(str(i)) for i in range(mx + 1)]
        return conv
    return v


def normalize(v):
    """Gli array scritti diventano oggetti con chiavi "0","1",… (come li tiene Firebase)."""
    if isinstance(v, list):
        return {str(i): normalize(x) for i, x in enumerate(v) if x is not None}
    if isinstance(v, dict):
        return {k: normalize(x) for k, x in v.items() if x is not None}
    return v


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        gz = "gzip" in (self.headers.get("Accept-Encoding") or "")
        if gz:  # come i server di Google: risposta compressa se il client la accetta
            body = gzip.compress(body)
        self.send_response(code)
        self._cors()
        if gz:
            self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, PUT, POST, PATCH, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Expose-Headers", "*")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(n).decode() if n else ""

    def _deny(self, method, path, uid):
        STATS["denied"] += 1
        if LOG:
            print("NEGATO", method, "/".join(path), uid)
        return self._send(401, {"error": "Permission denied"})

    def _db(self, method):
        u = urlparse(self.path)
        body = self._body() if method in ("PUT", "PATCH") else ""
        if not u.path.startswith("/db/") or not u.path.endswith(".json"):
            return self._send(404, {"error": "not found"})
        path = [p for p in u.path[4:-5].split("/") if p]
        uid = TOKENS.get(parse_qs(u.query).get("auth", [""])[0])
        if uid is None:
            return self._send(401, {"error": "Permission denied"})
        if FLAKY and random.random() < FLAKY:
            STATS["flaky"] += 1
            return self._send(503, {"error": "servizio non disponibile (finto)"})
        with LOCK:
            STATS[method.lower()] += 1
            if method == "GET":
                if not can_read(uid, path):
                    return self._deny(method, path, uid)
                return self._send(200, firebase_json(get_at(TREE, path)))
            if method == "DELETE":
                new = copy.deepcopy(TREE)
                set_in(new, path, None)
                if not can_write(uid, path, TREE, new):
                    return self._deny(method, path, uid)
                set_in(TREE, path, None)
                return self._send(200, None)
            data = normalize(resolve(json.loads(body or "null")))
            if method == "PUT":
                new = copy.deepcopy(TREE)
                set_in(new, path, data)
                if not can_write(uid, path, TREE, new):
                    return self._deny(method, path, uid)
                set_in(TREE, path, data)
                return self._send(200, firebase_json(data))
            if method == "PATCH":
                if not isinstance(data, dict):
                    return self._send(400, {"error": "PATCH senza oggetto"})
                items = [(path + [p for p in k.split("/") if p], v) for k, v in data.items()]
                new = copy.deepcopy(TREE)
                for p, v in items:
                    set_in(new, p, v)
                for p, v in items:
                    if not can_write(uid, p, TREE, new):
                        return self._deny(method, p, uid)
                for p, v in items:
                    set_in(TREE, p, v)
                return self._send(200, firebase_json(data))
        self._send(405, {"error": "method"})

    def do_GET(self):
        if self.path.startswith("/stats"):
            return self._send(200, STATS)
        self._db("GET")

    def do_PUT(self):
        self._db("PUT")

    def do_PATCH(self):
        self._db("PATCH")

    def do_DELETE(self):
        self._db("DELETE")

    def do_POST(self):
        u = urlparse(self.path)
        body = self._body()
        with LOCK:
            COUNT[0] += 1
            n = COUNT[0]
        if u.path == "/signup":
            tok = "tok%d" % n
            TOKENS[tok] = "uid%d" % n
            return self._send(200, {"idToken": tok, "localId": "uid%d" % n, "refreshToken": "r" + tok, "expiresIn": "3600"})
        if u.path == "/refresh":
            old = parse_qs(body).get("refresh_token", [""])[0]
            uid = TOKENS.get(old[1:]) if old.startswith("r") else None
            if uid is None:
                return self._send(400, {"error": {"message": "INVALID_REFRESH_TOKEN"}})
            tok = "tok%d" % n
            TOKENS[tok] = uid
            return self._send(200, {"id_token": tok, "refresh_token": "r" + tok, "user_id": uid})
        if u.path == "/dump":  # solo per le prove
            return self._send(200, TREE)
        self._send(404, {"error": "not found"})


def load_rules(p):
    global RULES
    with open(p) as f:
        RULES = json.load(f)
    # controllo: tutte le espressioni si traducono
    def walk(n, where):
        for k, v in n.items():
            if k in (".read", ".write", ".validate") and isinstance(v, str):
                translate(v)
            elif isinstance(v, dict):
                walk(v, where + "/" + k)
    walk(RULES["rules"], "")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    here = os.path.dirname(os.path.abspath(__file__))
    rules = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "firebase", "database.rules.json")
    load_rules(rules)
    print("finto Firebase su http://127.0.0.1:%d (regole: %s)" % (port, os.path.relpath(rules)), flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
