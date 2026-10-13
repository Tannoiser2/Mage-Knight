#!/usr/bin/env python3
"""Prepara le immagini di riferimento per Meshy (meshy/riferimenti/<id>.png).

Nemici del gioco base: dal fronte del segnalino (immagine originale 1024 px del modulo TTS, oppure
assets/enemies/<id>.webp se manca) si tiene il cerchio dell'illustrazione senza l'anello, si
cancellano (inpainting) le icone dei valori (Armatura, Attacco, Fama, abilità), poi si scontorna il
soggetto su fondo trasparente con rembg.
Siti (village, monastery, keep, mage_tower): ritaglio dell'esagono dalla texture della tessera, solo
come riferimento visivo (genera_miniature.py li crea da testo, vedi PROMPT_SITI).

Uso:  python3 meshy/prepara_riferimenti.py [id ...]
Serve: pillow, numpy, opencv-python, rembg[cpu] (pip install "rembg[cpu]" opencv-python-headless).
Le immagini originali si cercano in MK_TTS_IMAGES (default: la cartella del modulo nel container).
"""
import glob
import json
import os
import re
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw

QUI = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(QUI, "..")
RIF = os.path.join(QUI, "riferimenti")
IMG = os.environ.get("MK_TTS_IMAGES", "/mnt/user-data/uploads/Mage Knight/Mods/Images/")
OBJS = os.environ.get("MK_TTS_OBJS", "/home/claude/work/objs.json")

# zone delle icone sul segnalino (frazioni del lato): x0, y0, x1, y1
ICONS = [
    (0.25, 0.00, 0.79, 0.28),   # Armatura in alto + resistenze + torre (Fortificato)
    (0.00, 0.27, 0.31, 0.69),   # Attacco a sinistra
    (0.73, 0.39, 1.00, 0.69),   # abilità a destra (Brutale, Velenoso…)
    (0.37, 0.75, 0.63, 1.00),   # Fama in basso
]
SITE_TILE = {  # sito -> (immagine della tessera, direzione dell'esagono)
    "village": None, "monastery": None, "keep": None, "mage_tower": None,
}
DIRS = {"center": (0, 0), "0": (-1, 0), "180": (1, 0), "60": (-0.5, 1.5), "120": (0.5, 1.5),
        "240": (0.5, -1.5), "300": (-0.5, -1.5)}


def cache(url):
    if not url:
        return None
    g = glob.glob(IMG + re.sub(r"[^A-Za-z0-9]", "", url) + ".*")
    return g[0] if g else None


def original_for(e, objs):
    """Immagine originale del fronte: quella (fronte o retro del segnalino TTS) più simile al webp."""
    ref = Image.open(os.path.join(ROOT, e["img"])).convert("RGB").resize((64, 64))
    best = None
    for g in e.get("guids", []):
        o = objs.get(g)
        for k in ("img", "img2"):
            p = cache(o.get(k)) if o else None
            if not p:
                continue
            im = Image.open(p).convert("RGB")
            d = np.asarray(ImageChops.difference(im.resize((64, 64)), ref)).sum()
            if best is None or d < best[0]:
                best = (d, im)
    return best[1] if best else Image.open(os.path.join(ROOT, e["img"])).convert("RGB")


def enemy_ref(im, session):
    import cv2
    from rembg import remove
    S = 1024
    im = im.convert("RGB").resize((S, S), Image.LANCZOS)
    a = np.asarray(im).copy()
    mask = np.zeros((S, S), np.uint8)
    for x0, y0, x1, y1 in ICONS:
        mask[int(y0 * S):int(y1 * S), int(x0 * S):int(x1 * S)] = 255
    a = cv2.inpaint(a, mask, 9, cv2.INPAINT_TELEA)
    # cerchio interno all'anello nero
    circ = Image.new("L", (S, S), 0)
    r = 0.455 * S
    ImageDraw.Draw(circ).ellipse((S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r), fill=255)
    base = Image.fromarray(a)
    out = remove(base, session=session)
    al = np.asarray(ImageChops.multiply(out.getchannel("A"), circ)).astype(np.float32)
    # niente tagli netti sulle zone ridipinte (Meshy ricostruisce meglio una sagoma morbida):
    # si tolgono solo gli aloni semitrasparenti
    al[al < 140] = 0
    # si tengono solo i pezzi grandi (via briciole e aloni)
    n, lab, st, _ = cv2.connectedComponentsWithStats((al > 0).astype(np.uint8), 8)
    if n > 1:
        big = st[1:, cv2.CC_STAT_AREA].max()
        keep = np.zeros(n, bool)
        keep[1:] = st[1:, cv2.CC_STAT_AREA] >= 0.04 * big
        al[~keep[lab]] = 0
    out.putalpha(Image.fromarray(al.astype(np.uint8)))
    return square(out)


def square(out, S=1024, pad=0.08):
    bb = out.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    if bb:
        out = out.crop(bb)
    side = int(max(out.size) * (1 + 2 * pad))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(out, ((side - out.width) // 2, (side - out.height) // 2), out)
    return sq.resize((768, 768), Image.LANCZOS)


def site_refs(ids):
    tiles = json.load(open(os.path.join(ROOT, "data/tiles.json")))
    tl = tiles.get("tiles", tiles) if isinstance(tiles, dict) else tiles
    tl = tl if isinstance(tl, list) else list(tl.values())
    for t in tl:
        for d, h in (t.get("hexes") or {}).items():
            s = h.get("site") if isinstance(h, dict) else None
            if s in SITE_TILE and SITE_TILE[s] is None and t.get("set") == "base":
                SITE_TILE[s] = (t["img"], d)
    for s, v in SITE_TILE.items():
        if v is None or (ids and s not in ids):
            continue
        im = Image.open(os.path.join(ROOT, v[0])).convert("RGBA")
        w, h = im.size
        k = w / 2048.0
        r = 394 * k
        dx, dy = DIRS[v[1]]
        cx = 1024 * k + dx * 3 ** 0.5 * r
        cy = 985 * k + dy * r
        crop = im.crop((int(cx - r), int(cy - r), int(cx + r), int(cy + r)))
        m = Image.new("L", crop.size, 0)
        pts = []
        import math
        for i in range(6):
            ang = math.radians(60 * i - 90)
            pts.append((crop.width / 2 + r * 0.97 * math.cos(ang), crop.height / 2 + r * 0.97 * math.sin(ang)))
        ImageDraw.Draw(m).polygon(pts, fill=255)
        crop.putalpha(m)
        crop.resize((768, 768), Image.LANCZOS).save(os.path.join(RIF, "site_%s.png" % s))
        print("site_%s <- %s %s" % (s, v[0], v[1]))


def main():
    ids = sys.argv[1:]
    os.makedirs(RIF, exist_ok=True)
    objs = {o["guid"]: o for o in json.load(open(OBJS))} if os.path.exists(OBJS) else {}
    en = json.load(open(os.path.join(ROOT, "data/enemies.json")))["enemies"]
    todo = [e for e in en.values() if e.get("set") == "base" and (not ids or e["id"] in ids)]
    if todo:
        from rembg import new_session
        session = new_session(os.environ.get("REMBG_MODEL", "isnet-general-use"))
        for e in todo:
            enemy_ref(original_for(e, objs), session).save(os.path.join(RIF, e["id"] + ".png"))
            print(e["id"])
    site_refs([i.replace("site_", "") for i in ids])


if __name__ == "__main__":
    main()
