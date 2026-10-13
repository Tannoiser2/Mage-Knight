#!/usr/bin/env python3
"""Genera le miniature 3D di Mage Knight con Meshy.

Uso:
    export MESHY_API_KEY=la_tua_chiave
    python3 meshy/genera_miniature.py                 # tutte quelle che mancano (nemici + siti)
    python3 meshy/genera_miniature.py nemici          # solo i 29 tipi di nemico del gioco base
    python3 meshy/genera_miniature.py siti            # solo le strutture dei siti (12)
    python3 meshy/genera_miniature.py high_dragon minotaur site_keep   # solo alcune
    python3 meshy/genera_miniature.py --rifai medusa  # rigenera anche se esiste già
    python3 meshy/genera_miniature.py --elenco        # mostra l'elenco e cosa manca
    python3 meshy/genera_miniature.py --prova         # controlla tutto senza spendere crediti
    python3 meshy/genera_miniature.py --comprimi      # solo comprime i .glb pesanti già scaricati (gratis)
    python3 meshy/genera_miniature.py --da-testo gunners medusa    # solo questi, da testo invece che da immagine
    python3 meshy/genera_miniature.py --da-immagine monks          # solo questo, da immagine anche se è in DA_TESTO

Senza MESHY_API_KEY usa la riga di comando di Meshy (`meshy`, oppure
`npx --yes --package=meshy-cli@0.4.0 -- meshy`), che si collega con il browser:
    meshy auth login --device

Nemici: immagine → 3D, da meshy/riferimenti/<id>.png (preparate da prepara_riferimenti.py).
Siti (site_village, site_monastery, site_keep, site_mage_tower, site_dungeon, site_tomb, site_ruins,
site_camp, site_maze, site_labyrinth, site_pyramid, site_ziggurat): immagine → 3D dal disegno scontornato
meshy/riferimenti/site_<id>.png (con --siti-da-testo invece testo → 3D con i prompt SITI).
Il modello si salva in assets/miniatures/<id>.glb: il gioco lo usa da solo (MKMiniatures), basta
riaprire il progetto in Godot o rifare la build (la action di GitHub importa i .glb).

Modelli leggeri per il web (≈8000 triangoli i nemici, 10000 i siti). Dopo lo scaricamento ogni .glb
viene compresso con gltf-transform (via npx, serve Node.js): texture a 1024 px e, se serve, meno
triangoli; l'originale resta in meshy/originali/ (escluso da git). Ogni modello costa crediti:
lo script salta quelli già presenti, a meno di --rifai. Solo libreria standard di Python.
"""
import base64
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

API_IMG = "https://api.meshy.ai/openapi/v1/image-to-3d"
API_TXT = "https://api.meshy.ai/openapi/v2/text-to-3d"
QUI = os.path.dirname(os.path.abspath(__file__))
RIF = os.path.join(QUI, "riferimenti")
OUT = os.path.join(QUI, "..", "assets", "miniatures")
POLY_NEMICI = 8000
POLY_SITI = 10000

# tipi di nemico del gioco base (id = file in assets/enemies e data/enemies.json)
NEMICI = {
    # Orchi Predoni (verdi)
    "diggers": "Scavatori", "cursed_hags": "Megere Maledette", "ironclads": "Corazzati",
    "prowlers": "Predatori", "wolf_riders": "Cavalca Lupi", "orc_summoners": "Orchi Evocatori",
    # guarnigioni delle fortezze (grigi)
    "swordsmen": "Spadaccini", "golems": "Golem", "crossbowmen": "Balestrieri", "guardsmen": "Guardie",
    # sotterranei e tane (marroni)
    "gargoyle": "Gargoyle", "crypt_worm": "Verme delle Cripte", "werewolf": "Lupo Mannaro",
    "minotaur": "Minotauro", "medusa": "Medusa",
    # torri magiche (viola)
    "ice_golems": "Golem di Ghiaccio", "fire_golems": "Golem di Fuoco", "monks": "Monaci",
    "ice_mages": "Maghi del Ghiaccio", "illusionists": "Illusionisti", "fire_mages": "Maghi del Fuoco",
    # Draconum (rossi)
    "swamp_dragon": "Drago di Palude", "high_dragon": "Drago Supremo", "ice_dragon": "Drago di Ghiaccio",
    "fire_dragon": "Drago di Fuoco",
    # città (bianchi)
    "altem_guardsmen": "Guardie di Altem", "altem_mages": "Maghi di Altem", "freezers": "Congelatori",
    "gunners": "Artiglieri",
}

# descrizioni per testo → 3D (per i nemici si usa l'immagine; il testo per quelli in DA_TESTO,
# i cui segnalini sono scene affollate da cui non esce una sagoma pulita, o con --da-testo <id>)
PROMPT_NEMICI = {
    "diggers": "orc sapper with a shovel and pickaxe, crouching over a dug-up mound of earth",
    "cursed_hags": "hunched orc witch hag with wild hair, bone staff and ragged robes, casting a curse",
    "ironclads": "heavily armoured orc warrior in crude iron plate armour with a big axe",
    "prowlers": "lean orc scout warrior with a spear and skull trophies, sneaking",
    "wolf_riders": "orc warrior riding a huge black wolf, axe raised",
    "orc_summoners": "orc shaman summoner with a staff, ghostly smoke rising around him",
    "swordsmen": "imperial soldier with sword and kite shield, plate armour, helmet",
    "golems": "massive stone golem made of rough grey rock, glowing yellow eyes",
    "crossbowmen": "medieval imperial crossbowman in padded armour and kettle helmet, aiming a crossbow",
    "guardsmen": "imperial castle guard in full plate armour and closed helmet, standing with a halberd",
    "gargoyle": "winged stone gargoyle crouching, horns and claws, grey-green stone",
    "crypt_worm": "giant pale crypt worm bursting out of the ground, ring of teeth, slimy segments",
    "werewolf": "snarling werewolf, half man half wolf, grey fur, claws out",
    "minotaur": "black-furred minotaur with big horns, wielding a great axe",
    "medusa": "medusa gorgon woman with snakes for hair and a scaly serpent tail",
    "ice_golems": "golem made of jagged blue ice crystals, frosty",
    "fire_golems": "golem made of molten lava rock with glowing cracks of fire",
    "monks": "warrior monk in white robes with a hood, holding a staff, serene pose",
    "ice_mages": "sorcerer in frost-blue robes conjuring shards of ice",
    "illusionists": "mysterious violet-robed illusionist mage with a mask, swirling magic",
    "fire_mages": "sorcerer in dark red and gold robes with a horned crown, casting fire",
    "swamp_dragon": "green swamp dragon with a crocodile-like head, coiled, dripping venom",
    "high_dragon": "majestic golden dragon with a crest of spikes, wings folded",
    "ice_dragon": "pale blue ice dragon with crystalline spikes, roaring",
    "fire_dragon": "red fire dragon breathing flames, wings spread",
    "altem_guardsmen": "elite paladin guard of the city of Altem in ornate silver armour with tower shield and spear",
    "altem_mages": "elite battle mage of Altem in white and silver robes with a glowing staff",
    "freezers": "frost knight in icy white armour with a frozen lance, breath of cold",
    "gunners": "dwarf-like artilleryman in heavy armour carrying a fire cannon on his shoulder",
}
DA_TESTO = {"altem_mages", "crossbowmen", "freezers", "illusionists", "monks", "gunners", "fire_mages",
            "fire_dragon", "swamp_dragon", "crypt_worm"}

STILE = ("fantasy tabletop miniature, single piece on a small round base, hand-painted look, "
         "medieval high fantasy, Mage Knight board game style")
SITI = {
    "site_village": ("Villaggio", "a small medieval fantasy village: three timber-framed cottages with thatched roofs "
                     "around a well, " + STILE),
    "site_monastery": ("Monastero", "a medieval fantasy stone monastery with a bell tower, cloister walls and "
                       "a small chapel, " + STILE),
    "site_keep": ("Fortezza", "a medieval fantasy stone keep: square castle tower with battlements, "
                  "short curtain wall and a wooden gate, " + STILE),
    "site_mage_tower": ("Torre magica", "a tall slender fantasy mage tower of dark stone with a pointed violet roof, "
                        "glowing arcane windows and floating crystals, " + STILE),
    # siti aggiunti (solo immagine → 3D dal disegno della tessera; il prompt serve solo con --siti-da-testo)
    "site_dungeon": ("Sotterraneo", "ruined stone entrance to an underground dungeon, broken walls and stairs, " + STILE),
    "site_tomb": ("Tomba", "ancient pale stone tomb with obelisks and a dark entrance, " + STILE),
    "site_ruins": ("Antiche Rovine", "ancient circular stone ruins with broken columns, " + STILE),
    "site_camp": ("Campo Profughi", "refugee camp of striped tents and carts on a sandy base, " + STILE),
    "site_maze": ("Dedalo", "three round stone mazes joined together, sandstone walls, " + STILE),
    "site_labyrinth": ("Labirinto", "ancient sandstone labyrinth city with round towers, " + STILE),
    "site_pyramid": ("Piramide", "stepped sandstone pyramid with a gate building, " + STILE),
    "site_ziggurat": ("Ziggurat", "mesopotamian sandstone ziggurat with terraces and gate, " + STILE),
}


# ---------------------------------------------------------------- API REST (chiave)

def chiama(metodo, url, chiave, corpo=None):
    dati = json.dumps(corpo).encode() if corpo is not None else None
    rq = urllib.request.Request(url, data=dati, method=metodo)
    rq.add_header("Authorization", "Bearer " + chiave)
    if dati is not None:
        rq.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(rq, timeout=120) as r:
        return json.loads(r.read().decode())


def aspetta(url, tid, chiave):
    while True:
        time.sleep(10)
        st = chiama("GET", f"{url}/{tid}", chiave)
        stato = st.get("status")
        print(f"  {stato} {st.get('progress', 0)}%")
        if stato == "SUCCEEDED":
            return st
        if stato in ("FAILED", "CANCELED", "EXPIRED"):
            print(f"  non riuscito: {st.get('task_error')}")
            return None


def scarica(st, mid):
    url = (st.get("model_urls") or {}).get("glb")
    if not url:
        print("  nessun .glb nella risposta")
        return False
    os.makedirs(OUT, exist_ok=True)
    dest = os.path.join(OUT, mid + ".glb")
    urllib.request.urlretrieve(url, dest)
    print(f"  salvato {os.path.relpath(dest)} ({os.path.getsize(dest) // 1024} KB)")
    comprimi(dest, POLY_SITI if mid in SITI else POLY_NEMICI, nuovo=True)
    return True


# ---------------------------------------------------------------- compressione (gltf-transform)

GLTF = ["npx", "--yes", "@gltf-transform/cli@4.1.1"]
ORIGINALI = os.environ.get("MINIATURE_ORIGINALI") or os.path.join(QUI, "originali")  # copie dei .glb scaricati (non vanno su git)
TEXTURE = 1024                                 # lato massimo delle texture


def gltf_tool():
    if shutil.which("gltf-transform"):
        return ["gltf-transform"]
    return GLTF if shutil.which("npx") else None


def conta_glb(path):
    """(triangoli, vertici) di un .glb, leggendo solo l'intestazione JSON."""
    import struct
    with open(path, "rb") as f:
        f.read(12)
        lung, _ = struct.unpack("<II", f.read(8))
        j = json.loads(f.read(lung))
    acc = j.get("accessors", [])
    tri = vert = 0
    for m in j.get("meshes", []):
        for p in m.get("primitives", []):
            n = acc[p["attributes"]["POSITION"]]["count"]
            vert += n
            tri += (acc[p["indices"]]["count"] if "indices" in p else n) // 3
    return tri, vert


def riduci_mappe(path, lato=TEXTURE // 2):
    """Normal map e metallic/roughness a `lato` px (il colore resta a TEXTURE): su una miniatura così
    piccola non si vede differenza e il gioco pesa meno. Serve Pillow; senza, non fa nulla."""
    try:
        from PIL import Image
    except ImportError:
        return False
    import io
    import struct
    with open(path, "rb") as f:
        dati = f.read()
    lung = struct.unpack_from("<I", dati, 12)[0]
    j = json.loads(dati[20:20 + lung])
    bin_off = 20 + lung + 8
    binario = dati[bin_off:bin_off + struct.unpack_from("<I", dati, 20 + lung)[0]]
    if len(j.get("buffers", [])) != 1:
        return False
    piccole = set()
    for m in j.get("materials", []):
        for t in (m.get("normalTexture"), m.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture")):
            if t is not None:
                piccole.add(j["textures"][t["index"]]["source"])
    viste = [bytes(binario[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]) for v in j["bufferViews"]]
    cambiato = False
    for i in piccole:
        im = j["images"][i]
        if "bufferView" not in im:
            continue
        img = Image.open(io.BytesIO(viste[im["bufferView"]]))
        if max(img.size) <= lato:
            continue
        img = img.convert("RGB").resize((lato, lato * img.size[1] // img.size[0]), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, "JPEG", quality=88)
        viste[im["bufferView"]] = out.getvalue()
        im["mimeType"] = "image/jpeg"
        cambiato = True
    if not cambiato:
        return False
    nuovo = bytearray()
    for v, b in zip(j["bufferViews"], viste):
        nuovo += b"\0" * (-len(nuovo) % 4)
        v["byteOffset"] = len(nuovo)
        v["byteLength"] = len(b)
        nuovo += b
    nuovo += b"\0" * (-len(nuovo) % 4)
    j["buffers"][0]["byteLength"] = len(nuovo)
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    tot = 12 + 8 + len(js) + 8 + len(nuovo)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, tot))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(nuovo), 0x004E4942) + bytes(nuovo))
    return True


def imposta_import():
    """Impostazioni di importazione di Godot per assets/miniatures: texture estratte con compressione
    con perdita (WebP), .glb senza LOD né mesh d'ombra, così il .pck per il web resta piccolo.
    Va rieseguito dopo che Godot ha importato i .glb nuovi (crea lui i file .import)."""
    n = 0
    for nome in sorted(os.listdir(OUT)):
        if not nome.endswith((".jpg.import", ".glb.import")):
            continue
        p = os.path.join(OUT, nome)
        with open(p) as f:
            testo = f.read()
        # .glb: niente LOD né mesh d'ombra (miniature piccole: il .pck per il web pesa la metà)
        nuovo = testo.replace("meshes/generate_lods=true", "meshes/generate_lods=false")
        nuovo = nuovo.replace("meshes/create_shadow_meshes=true", "meshes/create_shadow_meshes=false")
        nuovo = nuovo.replace("compress/mode=0", "compress/mode=1").replace("compress/lossy_quality=0.7",
                                                                           "compress/lossy_quality=0.8")
        nuovo = nuovo.replace("detect_3d/compress_to=1", "detect_3d/compress_to=0")  # resta WebP anche nell'editor
        if nuovo != testo:
            with open(p, "w") as f:
                f.write(nuovo)
            n += 1
    return n


def comprimi(path, poly=POLY_NEMICI, nuovo=False):
    """Rende leggero un .glb di Meshy (20–180 MB → ~1–2 MB): texture a 1024 e, se i triangoli sono
    troppi (testo → 3D ignora il limite), weld + simplify. L'originale resta in meshy/originali/."""
    g = gltf_tool()
    if not g:
        print("  (gltf-transform non trovato: installa Node.js per comprimere; il file resta pesante)")
        return False
    os.makedirs(ORIGINALI, exist_ok=True)
    orig = os.path.join(ORIGINALI, os.path.basename(path))
    if nuovo or not os.path.exists(orig):   # appena scaricato: sostituisce l'originale vecchio
        shutil.copy2(path, orig)
    tmp = path + ".tmp.glb"
    try:
        tri, vert = conta_glb(orig)
        src = orig
        if tri > 2 * poly:
            ratio = max(0.001, min(1.0, 1.2 * poly / max(1, vert)))
            for cmd in (["weld", src, tmp], ["simplify", tmp, tmp, "--ratio", f"{ratio:.4f}", "--error", "0.02"]):
                subprocess.run(g + cmd, check=True, capture_output=True, text=True)
            src = tmp
        subprocess.run(g + ["resize", src, tmp, "--width", str(TEXTURE), "--height", str(TEXTURE)],
                       check=True, capture_output=True, text=True)
        os.replace(tmp, path)
    except (subprocess.CalledProcessError, OSError, ValueError, KeyError) as e:
        print(f"  compressione non riuscita: {getattr(e, 'stderr', '') or e}"[:400])
        if os.path.exists(tmp):
            os.remove(tmp)
        return False
    riduci_mappe(path)
    t2, _ = conta_glb(path)
    print(f"  compresso {os.path.relpath(path)} ({os.path.getsize(path) // 1024} KB, {tri} → {t2} triangoli)")
    return True


def data_uri(img):
    with open(img, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def api_da_immagine(mid, img, chiave, poly):
    compito = chiama("POST", API_IMG, chiave, {
        "image_url": data_uri(img),
        "enable_pbr": False,
        "should_remesh": True,
        "topology": "triangle",
        "target_polycount": poly,      # leggero: deve girare anche nel browser
        "should_texture": True,
    })
    tid = compito.get("result")
    print(f"  compito {tid}")
    st = aspetta(API_IMG, tid, chiave)
    return scarica(st, mid) if st else False


def api_da_testo(mid, prompt, chiave, poly):
    pre = chiama("POST", API_TXT, chiave, {
        "mode": "preview", "prompt": prompt, "art_style": "realistic",
        "should_remesh": True, "topology": "triangle", "target_polycount": poly,
    })
    pid = pre.get("result")
    print(f"  anteprima {pid}")
    if not aspetta(API_TXT, pid, chiave):
        return False
    ref = chiama("POST", API_TXT, chiave, {"mode": "refine", "preview_task_id": pid, "enable_pbr": False})
    rid = ref.get("result")
    print(f"  texture {rid}")
    st = aspetta(API_TXT, rid, chiave)
    return scarica(st, mid) if st else False


# ---------------------------------------------------------------- riga di comando di Meshy (login)

def cli():
    if shutil.which("meshy"):
        return ["meshy"]
    if shutil.which("npx"):
        return ["npx", "--yes", "--package=meshy-cli@0.4.0", "--", "meshy"]
    return None


def esegui(cmd):
    r = subprocess.run(cmd + ["--output-schema", "v1", "--format", "json", "--no-update-check"],
                       capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except ValueError:
        print("  risposta non leggibile:", (r.stdout + r.stderr)[-400:])
        return None


def cerca(d, chiave):
    """Primo valore di `chiave` in un JSON annidato."""
    if isinstance(d, dict):
        if chiave in d:
            return d[chiave]
        for v in d.values():
            x = cerca(v, chiave)
            if x is not None:
                return x
    elif isinstance(d, list):
        for v in d:
            x = cerca(v, chiave)
            if x is not None:
                return x
    return None


def cli_compito(base, risorsa, args, mid):
    r = esegui(base + [risorsa, "create"] + args + ["--target-formats", "glb", "--async"])
    tid = cerca(r, "task_id") if r else None
    if not tid:
        print("  invio non riuscito:", json.dumps(r)[:400] if r else "")
        return None
    print(f"  compito {tid}")
    w = esegui(base + [risorsa, "wait", tid, "--timeout", "1200"])
    st = cerca(w, "status") if w else None
    if st and str(st).upper() not in ("SUCCEEDED", "SUCCESS", "COMPLETED"):
        print(f"  stato {st}")
    g = esegui(base + [risorsa, "get", tid])
    return tid, g


def cli_scarica(g, mid):
    urls = cerca(g, "model_urls") or {}
    url = urls.get("glb") if isinstance(urls, dict) else None
    if not url:
        print("  nessun .glb:", json.dumps(g)[:300])
        return False
    return scarica({"model_urls": {"glb": url}}, mid)


def cli_da_immagine(base, mid, img, poly):
    r = cli_compito(base, "image-to-3d", ["--image-url", img, "--model-type", "smart-topology",
                                         "--target-polycount", str(poly), "--should-texture", "true"], mid)
    return cli_scarica(r[1], mid) if r else False


def cli_da_testo(base, mid, prompt, poly):
    # senza remesh l'anteprima esce da 1–5 milioni di triangoli (e la texture a 4k): chiediamo il
    # limite di poligoni e texture 2k, e comunque comprimi() alleggerisce il file dopo lo scaricamento
    remesh = json.dumps({"should_remesh": True, "topology": "triangle", "target_polycount": poly})
    r = cli_compito(base, "text-to-3d", ["--mode", "preview", "--prompt", prompt, "--data", remesh], mid)
    if not r:
        return False
    r2 = cli_compito(base, "text-to-3d", ["--mode", "refine", "--preview-task-id", r[0],
                                         "--texture-resolution", "2k"], mid)
    return cli_scarica(r2[1], mid) if r2 else False


# ---------------------------------------------------------------- principale

def prompt_di(mid):
    return SITI[mid][1] if mid in SITI else PROMPT_NEMICI[mid] + ", " + STILE


def main():
    argv = sys.argv[1:]
    rifai = "--rifai" in argv
    prova = "--prova" in argv
    # siti: immagine → 3D dal ritaglio del disegno (riferimenti/site_<id>.png); testo solo se richiesto
    testo_siti = "--siti-da-testo" in argv
    testo_forzato = set(argv[argv.index("--da-testo") + 1:]) if "--da-testo" in argv else set()
    img_forzata = set(argv[argv.index("--da-immagine") + 1:]) if "--da-immagine" in argv else set()
    args = [a for a in argv if not a.startswith("--")]
    tutti = list(NEMICI) + list(SITI)
    ids = []
    for a in args or ["nemici", "siti"]:
        ids += list(NEMICI) if a == "nemici" else list(SITI) if a == "siti" else [a]
    if "--elenco" in argv:
        for mid in tutti:
            c = "c'è" if os.path.exists(os.path.join(OUT, mid + ".glb")) else "manca"
            r = "riferimento ok" if os.path.exists(os.path.join(RIF, mid + ".png")) else "senza riferimento"
            print(f"{mid:18} {(NEMICI.get(mid) or SITI[mid][0]):22} {c:6} {r}")
        return
    if "--comprimi" in argv:   # solo compressione dei .glb già scaricati (nessun credito)
        for mid in ids:
            p = os.path.join(OUT, mid + ".glb")
            if not os.path.exists(p):
                continue
            if rifai or os.path.getsize(p) > 3 * 1024 * 1024:
                print(f"{mid}:")
                comprimi(p, POLY_SITI if mid in SITI else POLY_NEMICI)
            elif riduci_mappe(p):
                print(f"{mid}: mappe ridotte ({os.path.getsize(p) // 1024} KB)")
        n = imposta_import()
        if n:
            print(f"{n} file .import aggiornati (riapri Godot o esegui godot --headless --import per applicarli)")
        return
    chiave = os.environ.get("MESHY_API_KEY", "")
    base = None if chiave else cli()
    if not chiave and not base and not prova:
        sys.exit("Imposta la chiave (export MESHY_API_KEY=...) oppure installa la riga di comando di Meshy (npm).")
    if base and not prova:
        st = subprocess.run(base + ["auth", "status", "--format", "json", "--no-update-check"], capture_output=True, text=True)
        try:
            autenticato = cerca(json.loads(st.stdout), "authenticated") is True
        except ValueError:
            autenticato = False
        if not autenticato:
            print("Meshy: accesso non verificato. Esegui prima:  " + " ".join(base) + " auth login --device")
    fatti = 0
    for mid in ids:
        if mid not in NEMICI and mid not in SITI:
            print(f"{mid}: id sconosciuto (vedi --elenco)")
            continue
        if not rifai and os.path.exists(os.path.join(OUT, mid + ".glb")):
            print(f"{mid}: c'è già, salto")
            continue
        img = os.path.join(RIF, mid + ".png")
        testo = (mid in SITI and testo_siti) or (mid in NEMICI and (mid in DA_TESTO or mid in testo_forzato)
                                                 and mid not in img_forzata)
        if not testo and not os.path.exists(img):
            print(f"{mid}: manca l'immagine {os.path.relpath(img)} (python3 meshy/prepara_riferimenti.py)")
            continue
        print(f"{mid}: {NEMICI.get(mid) or SITI[mid][0]} ({'testo' if testo else 'immagine'} → 3D)")
        if prova:
            continue
        poly = POLY_SITI if mid in SITI else POLY_NEMICI
        try:
            if chiave:
                ok = api_da_testo(mid, prompt_di(mid), chiave, poly) if testo else api_da_immagine(mid, img, chiave, poly)
            else:
                ok = cli_da_testo(base, mid, prompt_di(mid), poly) if testo else cli_da_immagine(base, mid, img, poly)
            fatti += 1 if ok else 0
        except urllib.error.HTTPError as e:
            print(f"  errore {e.code}: {e.read().decode()[:300]}")
            if e.code in (401, 402, 403):
                sys.exit("Chiave non valida o crediti esauriti: mi fermo.")
    print(f"Fatto: {fatti} modelli nuovi in {os.path.relpath(OUT)}")


if __name__ == "__main__":
    main()
