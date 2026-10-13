#!/usr/bin/env python3
"""Genera le versioni ITALIANE delle carte Azione base (che nel modulo TTS esistono solo in inglese).

Per ogni carta base: parte dall'originale inglese in assets/cards/en/<id>.webp (se manca, ci copia
l'immagine attuale di assets/cards/<id>.webp, che a quel punto e' ancora l'originale inglese),
cancella titolo e testi (inpainting OpenCV + grana sintetica) e scrive titolo/testi italiani presi da
data/cards_basic.json (name_it / text_it, con alcune correzioni tipografiche qui sotto in OVERRIDES).
Risultato in assets/cards/<id>.webp (500x700 WebP q85). Rieseguibile: riparte sempre dagli originali.

Font: titolo Cinzel (assets/fonts/Cinzel.ttf, peso 560); testo Alegreya Sans Medium/Bold
(tools/fonts/, OFL) - umanistico simile al font delle carte ufficiali; numeri in grassetto.

Uso:  python3 tools/italianize_basics.py [id ...]      (senza argomenti: tutte le carte in CARD_IDS)
      python3 tools/italianize_basics.py --sheet out.png  (anche un foglio di controllo)
"""
import json, os, re, shutil, sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CARDS_DIR = os.path.join(ROOT, "assets/cards")
EN_DIR = os.path.join(CARDS_DIR, "en")
FONT_TITLE = os.path.join(ROOT, "assets/fonts/Cinzel.ttf")
FONT_BODY = os.path.join(ROOT, "tools/fonts/AlegreyaSans-Medium.ttf")
FONT_BOLD = os.path.join(ROOT, "tools/fonts/AlegreyaSans-Bold.ttf")
DATA = os.path.join(ROOT, "data/cards_basic.json")

CARD_IDS = [
    # mazzo standard
    "stamina", "determination", "crystallize", "march", "tranquility", "concentration", "swiftness",
    "mana_draw", "promise", "improvisation", "threaten", "rage",
    # eroi base
    "battle_versatility", "mana_pull", "will_focus", "crystal_joy", "noble_manners", "rejuvenate",
    "cold_toughness", "instinct",
    # Wolfhawk, Krang, Braevalar
    "swift_reflexes", "tirelessness", "savage_harvesting", "ruthless_coercion", "druidic_paths",
    "one_with_the_land",
]

# Correzioni rispetto a text_it (dicitura della Guida al primo gioco / a capo come sugli originali).
# "\n" = a capo forzato.
OVERRIDES = {
    "tranquility": {"basic": "Cura 1 o pesca una carta.", "powered": "Cura 2 o pesca due carte."},
    "threaten": {"powered": "Influenza 5.\nReputazione -1."},
    "noble_manners": {"basic": "Influenza 2.\nFama +1 se la usi durante un'interazione.",
                      "powered": "Influenza 4.\nFama +1 e Reputazione +1 se la usi durante un'interazione."},
}

SS = 4  # supersampling del testo


# ---------------------------------------------------------------- analisi dell'immagine inglese
def lum(a):
    return a.mean(axis=2)


def find_banner(a):
    """Bounding box (x0,y0,x1,y1) dell'interno bianco del cartiglio del titolo."""
    L = lum(a.astype(int))
    sat = a.max(2).astype(int) - a.min(2).astype(int)
    wh = (L > 215) & (sat < 30)
    rows = set(y for y in range(330, 420) if wh[y, 110:390].sum() > 60)
    runs, y = [], 330
    while y < 420:  # strisce contigue (tollera 1 riga mancante)
        if y in rows:
            y0 = y1 = y
            while y1 + 1 in rows or y1 + 2 in rows:
                y1 += 1 if y1 + 1 in rows else 2
            runs.append((y0, y1))
            y = y1 + 1
        else:
            y += 1
    # il cartiglio e' alto ~30 px e sta intorno a y=362; l'arte chiara sopra puo' formare altre strisce
    runs = [r for r in runs if 22 <= r[1] - r[0] <= 40] or runs
    y0, y1 = min(runs, key=lambda r: abs(r[0] - 362))
    cols = np.where(wh[y0 + 3:y1 - 2].sum(0) > (y1 - y0) * 0.45)[0]
    return int(cols.min()), y0, int(cols.max()), y1


_GEM_T = None


def gem_template():
    global _GEM_T
    if _GEM_T is None:
        a = np.asarray(Image.open(os.path.join(EN_DIR, "stamina.webp")).convert("L")).astype(np.float32)
        _GEM_T = edges(a)[503:571, 160:342].copy()
    return _GEM_T


def edges(g):
    gx = cv2.Sobel(g, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(g, cv2.CV_32F, 0, 1, ksize=3)
    return cv2.magnitude(gx, gy)


def find_gem(a):
    """Rettangolo (x0,y0,x1,y1) dell'ornamento centrale con la gemma (tra effetto base e potenziato)."""
    g = cv2.cvtColor(a, cv2.COLOR_RGB2GRAY).astype(np.float32)
    e = edges(g)
    t = gem_template()
    win = e[470:620, 120:390]
    r = cv2.matchTemplate(win, t, cv2.TM_CCOEFF_NORMED)
    _, score, _, (mx, my) = cv2.minMaxLoc(r)
    x0, y0 = 120 + mx, 470 + my
    return x0, y0, x0 + t.shape[1], y0 + t.shape[0], score


def text_mask(a, box, cx):
    """Maschera dei pixel di testo scuro dentro box=(x0,y0,x1,y1); le righe si trovano nella banda centrale
    e si estendono ai lati a catena (spazi <= 16 px), cosi' le volute della cornice non vengono toccate."""
    x0, y0, x1, y1 = box
    L = lum(a.astype(int))
    dark = (L < 110).astype(np.uint8)
    sub = dark[y0:y1, x0:x1]
    n, lab, st, cen = cv2.connectedComponentsWithStats(sub, connectivity=8)
    m = np.zeros(a.shape[:2], np.uint8)
    comps = []
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if h > 50 or w > 60:
            continue
        # tocca il bordo del box: pezzo di cornice/cartiglio/gemma tagliato, oppure una lettera tagliata
        edge = x == 0 or y == 0 or x + w >= x1 - x0 or y + h >= y1 - y0
        # inchiostro del testo quasi nero; le volute della cornice sono piu' chiare/colorate
        lp = L[y0:y1, x0:x1][lab == i]
        ink = lp[lp <= np.percentile(lp, 40)].mean()
        if area >= 6 and (ink > 48 or (edge and ink > 30)):
            continue
        comps.append((x + x0, y + y0, w, h, i, edge))
    # righe: componenti (non di bordo) che intersecano la banda centrale
    band = [c for c in comps if not c[5] and c[0] < cx + 130 and c[0] + c[2] > cx - 130]
    lines = []
    for c in sorted(band, key=lambda c: c[1]):
        cy0, cy1 = c[1], c[1] + c[3]
        for ln in lines:
            if cy0 < ln[1] - 2 and cy1 > ln[0] + 2:
                ln[0], ln[1] = min(ln[0], cy0), max(ln[1], cy1)
                break
        else:
            lines.append([cy0, cy1])
    keep = set()
    lines = [ln for ln in lines if ln[1] - ln[0] >= 8]  # scarta frammenti di cornice tagliati dal box
    for ly0, ly1 in lines:
        # tutte le componenti che toccano la riga (anche lettere fuse con la riga sotto/sopra)
        row = [c for c in comps if c[1] < ly1 - 2 and c[1] + c[3] > ly0 + 2]
        # i pezzi che toccano il bordo valgono solo se stanno per lo piu' dentro la riga (lettera tagliata)
        row = [c for c in row if not c[5] or (min(c[1] + c[3], ly1) - max(c[1], ly0)) >= 0.5 * c[3]]
        row.sort(key=lambda c: c[0])
        core = [c for c in row if not c[5] and c[0] < cx + 130 and c[0] + c[2] > cx - 130]
        if not core:
            continue
        left = min(c[0] for c in core)
        right = max(c[0] + c[2] for c in core)
        changed = True
        while changed:
            changed = False
            for c in row:
                if c[4] in keep:
                    continue
                if c[0] + c[2] >= left - 16 and c[0] <= right + 16:
                    keep.add(c[4])
                    left, right = min(left, c[0]), max(right, c[0] + c[2])
                    changed = True
    for i in keep:
        m[y0:y1, x0:x1][lab == i] = 1
    return grow(m, L, (x0, y0, x1, y1))


def grow(m, L, box, thr=170, steps=4):
    """Dilatazione geodetica: aggiunge i bordi sfumati delle lettere (pixel medio-scuri adiacenti)."""
    x0, y0, x1, y1 = box
    allow = np.zeros_like(m)
    allow[y0:y1, x0:x1] = (L[y0:y1, x0:x1] < thr)
    k = np.ones((3, 3), np.uint8)
    for _ in range(steps):
        m = np.maximum(m, cv2.dilate(m, k) & allow)
    return m


def erase(a, mask, dil=2, noise_ref=None):
    """Inpainting dei pixel in mask + grana simile alla pergamena circostante."""
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * dil + 1, 2 * dil + 1))
    m = cv2.dilate(mask, k)
    out = cv2.inpaint(a, m * 255, 6, cv2.INPAINT_TELEA)
    # grana: deviazione del dettaglio fine nell'intorno non mascherato
    ys, xs = np.where(m > 0)
    if len(ys):
        y0, y1, x0, x1 = max(ys.min() - 20, 0), ys.max() + 20, max(xs.min() - 20, 0), xs.max() + 20
        reg = a[y0:y1, x0:x1].astype(np.float32)
        hp = reg - cv2.GaussianBlur(reg, (0, 0), 2.0)
        free = cv2.dilate(m, k, iterations=3)[y0:y1, x0:x1] == 0
        sd = float(hp[free].std()) if free.sum() > 50 else 3.0
        sd = min(max(sd, 1.5), 7.0)
        rng = np.random.default_rng(1234)
        nz = rng.normal(0, sd, a.shape[:2]).astype(np.float32)
        nz = cv2.GaussianBlur(nz, (0, 0), 0.7) * 1.4
        feather = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 1.0)
        o = out.astype(np.float32) + (nz * feather)[..., None]
        out = np.clip(o, 0, 255).astype(np.uint8)
    return out


# ---------------------------------------------------------------- rendering del testo
def font(path, size, weight=None):
    f = ImageFont.truetype(path, size)
    if weight:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    return f


def tokens(text):
    """Divide in parole; ogni parola e' una lista di (testo, bold). Numeri (con segno) in grassetto."""
    # spazio non separabile prima di un numero ("Movimento 2", "Fama +1"): mai a capo tra parola e valore
    text = re.sub(r" (?=[+\-]?\d)", "\u00a0", text)
    words = []
    for w in text.split(" "):
        parts = []
        for p in re.split(r"([+\-]?\d+)", w):
            if p:
                parts.append((p, bool(re.fullmatch(r"[+\-]?\d+", p))))
        words.append(parts)
    return words


FEAT = ["lnum", "kern"]  # cifre allineate (Alegreya ha cifre "old style" di default)


def word_w(parts, fr, fb):
    return sum((fb if b else fr).getlength(t, features=FEAT) for t, b in parts)


def wrap(paras, fr, fb, maxw):
    lines = []
    sp = fr.getlength(" ")
    for para in paras:
        cur, cw = [], 0.0
        for w in tokens(para):
            ww = word_w(w, fr, fb)
            if cur and cw + sp + ww > maxw:
                lines.append(cur)
                cur, cw = [w], ww
            else:
                cw = cw + (sp if cur else 0) + ww
                cur.append(w)
        if cur:
            lines.append(cur)
    return lines


def line_w(line, fr, fb):
    return sum(word_w(w, fr, fb) for w in line) + fr.getlength(" ") * (len(line) - 1)


def layout(text, maxw, maxh, smax=25.0, smin=11.0):
    """Sceglie la dimensione piu' grande che entra, poi bilancia le righe (come sugli originali)."""
    paras = text.split("\n")
    s = smax
    while s >= smin:
        fr = font(FONT_BODY, round(s * SS))
        fb = font(FONT_BOLD, round(s * SS))
        lh = s * 1.17
        lines = wrap(paras, fr, fb, maxw * SS)
        h = lh * (len(lines) - 1) + s * 1.0
        if h <= maxh:
            # bilanciamento: larghezza minima che non aumenta il numero di righe
            lo, hi = maxw * 0.45, maxw
            n = len(lines)
            for _ in range(14):
                mid = (lo + hi) / 2
                if len(wrap(paras, fr, fb, mid * SS)) <= n:
                    hi = mid
                else:
                    lo = mid
            lines = wrap(paras, fr, fb, hi * SS)
            return s, fr, fb, lines, lh
        s -= 0.5
    raise ValueError("testo troppo lungo: " + text)


def render_body(text, cx, cy, maxw, maxh, color, size_cap=25.0):
    """Ritorna (alpha L-mode 500x700, size) del testo centrato in (cx, cy)."""
    s, fr, fb, lines, lh = layout(text, maxw, maxh, smax=size_cap)
    W, H = 500 * SS, 700 * SS
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    asc = fr.getmetrics()[0]
    total = lh * (len(lines) - 1) + s
    top = cy - total / 2
    sp = fr.getlength(" ")
    for i, line in enumerate(lines):
        lw = line_w(line, fr, fb)
        x = cx * SS - lw / 2
        # baseline: cap height ~0.63 em in Alegreya Sans; centriamo l'altezza delle maiuscole
        base = (top + i * lh + s * 0.82) * SS
        for j, w in enumerate(line):
            for t, b in w:
                f = fb if b else fr
                d.text((x, base), t, font=f, fill=255, anchor="ls", features=FEAT)
                x += f.getlength(t, features=FEAT)
            x += sp
    return img.resize((500, 700), Image.LANCZOS), s


def render_title(title, banner, color):
    x0, y0, x1, y1 = banner
    maxw = (x1 - x0) - 20
    cx = (x0 + x1) / 2
    cy = (y0 + y1) / 2
    size = 27
    title = title.upper().replace("'", "\u2019")
    while True:
        f = font(FONT_TITLE, size * SS, 560)
        w = f.getlength(title)
        squeeze = min(1.0, maxw * SS / w)
        if squeeze >= 0.80 or size <= 18:
            break
        size -= 1
    W = int(w + 40 * SS)
    Hh = int(60 * SS)
    tmp = Image.new("L", (W, Hh), 0)
    d = ImageDraw.Draw(tmp)
    # centriamo verticalmente l'altezza delle maiuscole (gli accenti sporgono sopra)
    capb = f.getbbox("H", anchor="ls")
    caph = capb[3] - capb[1]
    base = Hh / 2 + caph / 2
    d.text((20 * SS, base), title, font=f, fill=255, anchor="ls")
    nw = max(1, int(round(W * squeeze)))
    tmp = tmp.resize((nw, Hh), Image.LANCZOS)
    tmp = tmp.resize((max(1, round(nw / SS)), round(Hh / SS)), Image.LANCZOS)
    out = Image.new("L", (500, 700), 0)
    out.paste(tmp, (int(round(cx - tmp.width / 2)), int(round(cy + 1 - tmp.height / 2))))
    return out, size, squeeze


def composite(img, alpha, color):
    a = np.asarray(alpha).astype(np.float32)[..., None] / 255.0
    a = np.clip(a * 1.08, 0, 1)
    col = np.array(color, np.float32)[None, None, :]
    o = img.astype(np.float32) * (1 - a) + col * a
    return np.clip(o, 0, 255).astype(np.uint8)


def ink_color(a, mask, default):
    px = a[mask > 0]
    if len(px) < 30:
        return default
    L = px.mean(1)
    sel = px[L <= np.percentile(L, 30)]
    return tuple(int(v) for v in sel.mean(0))


# ---------------------------------------------------------------- per carta
def process(cid, card, log):
    src = os.path.join(EN_DIR, cid + ".webp")
    a = np.asarray(Image.open(src).convert("RGB")).copy()
    bx0, by0, bx1, by1 = find_banner(a)
    gx0, gy0, gx1, gy1, score = find_gem(a)
    cx = (bx0 + bx1) / 2
    # --- cancellazione titolo
    L = lum(a.astype(int))
    tm = np.zeros(a.shape[:2], np.uint8)
    inner = (slice(by0 + 2, by1 - 1), slice(bx0 + 3, bx1 - 2))
    tm[inner] = (L[inner] < 175).astype(np.uint8)
    title_col = ink_color(a, (L < 120) & (tm > 0), (40, 32, 30))
    a = erase(a, tm, dil=2)
    # --- cancellazione testi
    basic_box = (40, by1 + 9, 460, gy0 + 10)
    pow_box = (40, gy1 - 2, 460, 674)
    m1 = text_mask(a, basic_box, cx)
    m2 = text_mask(a, pow_box, cx)
    body_col = ink_color(a, m1 | m2, (38, 30, 26))
    a = erase(a, m1, dil=2)
    a = erase(a, m2, dil=2)
    # --- testi italiani
    texts = dict(card["text_it"])
    texts.update(OVERRIDES.get(cid, {}))
    texts = {k: v.replace("'", "’") for k, v in texts.items()}
    talpha, tsize, sq = render_title(card["name_it"], (bx0, by0, bx1, by1), title_col)
    a = composite(a, talpha, title_col)
    # area base: da sotto il cartiglio a sopra la gemma; area potenziata: sotto la gemma fino alla cornice
    btop, bbot = by1 + 12, gy0 - 2
    ptop, pbot = gy1 - 4, 655
    bal, bs = render_body(texts["basic"], cx, (btop + bbot) / 2 + 3, 368, bbot - btop, body_col)
    a = composite(a, bal, body_col)
    pal, ps = render_body(texts["powered"], cx, (ptop + pbot) / 2 + 1, 356, pbot - ptop, body_col)
    a = composite(a, pal, body_col)
    log.append(f"{cid:20s} banner={bx0},{by0}-{bx1},{by1} gem_y={gy0}-{gy1} (match {score:.2f}) "
               f"title {tsize}px x{sq:.2f}  basic {bs}px  powered {ps}px")
    return Image.fromarray(a)


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    ids = argv or CARD_IDS
    data = json.load(open(DATA, encoding="utf-8"))
    by_id = {c["id"]: c for c in data["cards"]}
    os.makedirs(EN_DIR, exist_ok=True)
    gd = os.path.join(EN_DIR, ".gdignore")
    if not os.path.exists(gd):
        open(gd, "w").close()
    for cid in ids:  # salva gli originali inglesi una sola volta
        en = os.path.join(EN_DIR, cid + ".webp")
        if not os.path.exists(en):
            if by_id[cid].get("img_lang") == "it-gen":
                sys.exit(f"{cid}: manca l'originale inglese e l'immagine attuale e' gia' italiana")
            shutil.copy2(os.path.join(CARDS_DIR, cid + ".webp"), en)
    if not os.path.exists(os.path.join(EN_DIR, "stamina.webp")):
        shutil.copy2(os.path.join(CARDS_DIR, "stamina.webp"), os.path.join(EN_DIR, "stamina.webp"))
    log, outs = [], []
    for cid in ids:
        im = process(cid, by_id[cid], log)
        im.save(os.path.join(CARDS_DIR, cid + ".webp"), "WEBP", quality=85, method=6)
        outs.append(im)
    print("\n".join(log))
    # segna le carte nel JSON (modifica minima: build_actions.py non ha un hook per questo)
    changed = False
    for c in data["cards"]:
        if c["id"] in ids and c.get("img_lang") != "it-gen":
            c["img_lang"] = "it-gen"
            changed = True
    if changed:
        txt = open(DATA, encoding="utf-8").read()
        for cid in ids:
            # inserisce "img_lang" subito dopo "img" senza riformattare il file
            txt = re.sub(r'(\n([ \t]*)"img": "assets/cards/%s\.webp",)(?!\s*"img_lang")' % re.escape(cid),
                         r'\1\n\2"img_lang": "it-gen",', txt)
        json.loads(txt)
        open(DATA, "w", encoding="utf-8").write(txt)
    if sheet:
        cols = 6
        rows = (len(outs) + cols - 1) // cols
        S = Image.new("RGB", (cols * 250, rows * 350), "black")
        for i, im in enumerate(outs):
            S.paste(im.resize((250, 350), Image.LANCZOS), ((i % cols) * 250, (i // cols) * 350))
        S.save(sheet)


if __name__ == "__main__":
    main(sys.argv[1:])
