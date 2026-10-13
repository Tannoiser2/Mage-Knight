#!/usr/bin/env python3
"""Indice di tutte le carte del modulo TTS: guid, nome, mazzo, foglio (it/en), griglia, indice.

Uso:
  python3 tools/card_index.py                 -> scrive /home/claude/work/card_index.json
  from card_index import crop                 -> crop(entry, lang='it') restituisce un'immagine PIL
Sorgenti: /home/claude/work/mod.json (salvataggio TTS) e le immagini in /mnt/user-data/uploads/Mage Knight/Mods.
"""
import json, os, re, sys
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
MOD = '/home/claude/work/mod.json'
IMG = '/mnt/user-data/uploads/Mage Knight/Mods/Images'
OUT = '/home/claude/work/card_index.json'


def lang(s, want='it'):
    if not isinstance(s, str) or '{' not in s:
        return s
    parts = dict(re.findall(r'\{([a-z\-]+)\}([^{]*)', s))
    return parts.get(want) or parts.get('en') or s


def cache(u):
    return re.sub(r'[^A-Za-z0-9]', '', u or '')


_files = None


def local(url):
    global _files
    if _files is None:
        _files = {os.path.splitext(f)[0]: os.path.join(IMG, f) for f in os.listdir(IMG)}
    return _files.get(cache(url))


def build():
    d = json.load(open(MOD))
    lua = d['LuaScript']
    names = {}
    for g, body in re.findall(r'\["([0-9a-f]{6})"\]=\{([^\n]*)\}', lua):
        m = re.search(r'name=\{"([^"]*)"', body)
        t = re.search(r'cardType="([^"]*)"', body)
        if m:
            names[g] = (m.group(1), t.group(1) if t else '')
    out = []

    def walk(o, path, inh=None):
        nick_en = lang(o.get('Nickname', ''), 'en')
        decks = dict(inh or {})
        decks.update(o.get('CustomDeck') or {})
        if 'CardID' in o:
            cid = o['CardID']
            cd = decks.get(str(cid // 100))
            if cd:
                g = o.get('GUID')
                nm, ty = names.get(g, (nick_en, ''))
                out.append({
                    'guid': g, 'name': nm, 'lua_type': ty, 'nick_en': nick_en,
                    'nick_it': lang(o.get('Nickname', ''), 'it'), 'deck': path,
                    'face_it': local(lang(cd['FaceURL'], 'it')), 'face_en': local(lang(cd['FaceURL'], 'en')),
                    'back': local(lang(cd['BackURL'], 'it')), 'nw': cd['NumWidth'], 'nh': cd['NumHeight'],
                    'idx': cid % 100, 'cardid': cid,
                    'desc': lang(o.get('Description', ''), 'it')[:300],
                })
        for x in o.get('ContainedObjects') or []:
            walk(x, path + '/' + nick_en, decks)
        for s in (o.get('States') or {}).values():
            walk(s, path + '/' + nick_en + '#', decks)
    for o in d['ObjectStates']:
        walk(o, '')
    json.dump(out, open(OUT, 'w'), ensure_ascii=False, indent=1)
    return out


_sheets = {}


def crop(e, lang='it'):
    """Ritaglia la carta e (voce dell'indice) dal suo foglio. lang 'it' usa il foglio italiano se c'è."""
    f = e['face_it'] if lang == 'it' and e.get('face_it') else e['face_en']
    if f not in _sheets:
        _sheets.clear()
        _sheets[f] = Image.open(f).convert('RGB')
    im = _sheets[f]
    W, H = im.size
    cw, ch = W / e['nw'], H / e['nh']
    i = e['idx']
    x, y = i % e['nw'], i // e['nw']
    return im.crop((int(x * cw), int(y * ch), int((x + 1) * cw), int((y + 1) * ch)))


if __name__ == '__main__':
    out = build()
    import collections
    c = collections.Counter(e['deck'].split('/')[1] if e['deck'].count('/') else '(top)' for e in out)
    print(len(out), 'carte')
    for k, v in c.most_common():
        print(v, k)
