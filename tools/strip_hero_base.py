#!/usr/bin/env python3
"""Toglie dalle figure degli eroi (assets/models/hero_*.obj, dal modulo TTS) la basetta tronco-conica
originale (cava e senza texture: nel gioco sembrava una ciambella bianca con l'eroe che fluttua).
La figura poggia poi sulla basetta colorata disegnata dal tavolo 3D. Rieseguibile: salva l'originale
in assets/models/originali/ la prima volta e lavora sempre da lì."""
import glob, math, os, shutil
D = os.path.join(os.path.dirname(__file__), '..', 'assets', 'models')
O = os.path.join(D, 'originali')
os.makedirs(O, exist_ok=True)
open(os.path.join(O, '.gdignore'), 'w').close()
for f in sorted(glob.glob(os.path.join(D, 'hero_*.obj'))):
    orig = os.path.join(O, os.path.basename(f))
    if not os.path.exists(orig):
        shutil.copy(f, orig)
    lines = open(orig).read().splitlines()
    V = [tuple(map(float, l.split()[1:4])) for l in lines if l.startswith('v ')]
    ys = [v[1] for v in V]; y0, y1 = min(ys), max(ys)
    top = y0 + (y1 - y0) * 0.11            # sopra la basetta (alta ~8% della figura)
    def base_vert(i):
        x, y, z = V[i]
        r = math.hypot(x, z)
        return y < y0 + 0.02 * (y1 - y0) or (r > 0.70 and y < top)
    out, drop = [], 0
    for l in lines:
        if l.startswith('f '):
            idx = [int(t.split('/')[0]) - 1 for t in l.split()[1:]]
            if all(base_vert(i) for i in idx):
                drop += 1
                continue
        out.append(l)
    open(f, 'w').write('\n'.join(out) + '\n')
    print(os.path.basename(f), 'facce tolte', drop)
