#!/usr/bin/env python3
"""Ritaglia le immagini di Incantesimi, Artefatti, Unità e Abilità (agente MAGIC). Rieseguibile.

Legge data/cards_spells.json, data/cards_artifacts.json, data/units.json, data/skills.json
(campo "guid" = GUID dell'oggetto nel modulo TTS, "img_lang" = 'it'|'en') e scrive:
  assets/cards/<id>.webp              incantesimi, artefatti (+ <id>_attached.webp per gli stendardi)
  assets/cards/unit_<id>.webp         unità
  assets/skills/<id>.webp             abilità
  assets/cards/back_spell.webp, back_artifact.webp, back_unit_regular.webp, back_unit_elite.webp
Uso: python3 tools/build_magic.py [--force]
"""
import json, os, re, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from card_index import crop, lang, local  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
INDEX = '/home/claude/work/card_index.json'
MOD = '/home/claude/work/mod.json'
CARD_H = 700
FORCE = '--force' in sys.argv


def save(im, rel, h=None):
    out = os.path.join(ROOT, rel)
    if os.path.exists(out) and not FORCE:
        return
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im = im.convert('RGB')
    if h and im.height > h:
        im = im.resize((round(im.width * h / im.height), h), Image.LANCZOS)
    im.save(out, 'WEBP', quality=85, method=6)


def load(name, key):
    return json.load(open(os.path.join(ROOT, 'data', name)))[key]


def main():
    idx = {}
    for e in json.load(open(INDEX)):
        idx.setdefault(e['guid'], e)
    backs = {}
    n = 0
    for name, key, prefix, back in (('cards_spells.json', 'cards', '', 'back_spell'),
                                    ('cards_artifacts.json', 'cards', '', 'back_artifact'),
                                    ('units.json', 'units', 'unit_', None)):
        for c in load(name, key):
            e = idx[c['guid']]
            save(crop(e, c.get('img_lang', 'it')), c['img'], CARD_H)
            n += 1
            b = back or ('back_unit_elite' if c.get('elite') else 'back_unit_regular')
            if c.get('set') != 'fan' and e.get('back'):
                backs.setdefault(b, e['back'])
            if c.get('guid_attached'):
                ea = idx.get(c['guid_attached'])
                if ea:
                    save(crop(ea, 'it'), c['img_attached'], 400)
    for b, f in backs.items():
        save(Image.open(f), 'assets/cards/%s.webp' % b, CARD_H)
    # abilità: immagini Custom_Tile dal salvataggio TTS
    d = json.load(open(MOD))
    tiles = {}

    def walk(o):
        if o.get('Name') == 'Custom_Tile':
            tiles.setdefault(o['GUID'], o)
        for x in o.get('ContainedObjects') or []:
            walk(x)
        for s in (o.get('States') or {}).values():
            walk(s)
    for o in d['ObjectStates']:
        walk(o)
    back_done = False
    for s in load('skills.json', 'skills'):
        ci = tiles[s['guid']]['CustomImage']
        f = local(lang(ci['ImageURL'], 'it'))
        save(Image.open(f), s['img'])
        n += 1
        if not back_done and ci.get('ImageSecondaryURL'):
            fb = local(lang(ci['ImageSecondaryURL'], 'it'))
            if fb:
                save(Image.open(fb), 'assets/skills/back_%s.webp' % s['hero'])
    print(n, 'immagini;', 'retro:', sorted(backs))


if __name__ == '__main__':
    main()
