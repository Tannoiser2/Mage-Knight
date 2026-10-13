#!/bin/sh
# Calibrazione delle miniature dei siti sul disegno stampato delle tessere -> data/site_minis.json.
# Da lanciare dalla radice del progetto; file di lavoro in /tmp/site_calib (serve: pip install trimesh rembg).
#  1. masks.py    ritaglia gli esagoni con un sito e scontorna il disegno (rembg) -> /tmp/site_calib/m/
#  2. match2.py   prende un disegno-campione per sito (TPL in match.py: un esagono ben scontornato, oppure
#                 meshy/riferimenti/site_<sito>.png) e lo ritrova su ogni tessera (template matching) -> match2.json
#  3. yawgrid.py  <sito>: disegno + modello visto dalla telecamera iniziale a 8 orientamenti (scelta a occhio
#                 del centro di ricerca, tabella CH in final.py)
#  4. final2.py   <siti>: yaw/scala/posizione che massimizzano la sovrapposizione della sagoma vista a 55° col
#                 disegno, penalizzando la pianta che esce dal disegno -> fin_<sito>.json
#  5. build_json.py + front.py: scrive data/site_minis.json (sites, hexes) e la fascia "front" dei segnalini
#     (front.py stampa i valori; il blocco in fondo a run.sh li copia nel json).
# Controllo: tests/site_calib_shot.gd (screenshot dall'alto e di scorcio di ogni sito).
set -e
mkdir -p /tmp/site_calib
T=tools/site_calib
python3 $T/masks.py
python3 $T/match2.py
python3 $T/final2.py village monastery keep mage_tower dungeon tomb ruins camp maze labyrinth pyramid ziggurat
python3 $T/build_json.py
python3 $T/front.py > /dev/null
python3 - <<'PY'
import json
p='data/site_minis.json'
d=json.load(open(p)); f=json.load(open('/tmp/site_calib/front.json'))
for k,h in d['hexes'].items(): h['front']=round(min(0.78,max(0.56,f[k])),2)
for s,v in d['sites'].items():
    fr=[h['front'] for h in d['hexes'].values() if h['site']==s]; v['front']=round(sum(fr)/len(fr),2)
json.dump(d,open(p,'w'),indent=1,ensure_ascii=False)
PY
