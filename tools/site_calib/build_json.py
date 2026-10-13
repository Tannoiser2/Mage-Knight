import json,sys
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from fit import TPLI, R
M2=json.load(open('/tmp/site_calib/match2.json'))
SINK_MODEL={'dungeon':0.125}
p='data/site_minis.json'
old=json.load(open(p))
sites={}; hexes={}
for site in TPLI:
    f=json.load(open(f'/tmp/site_calib/fin_{site}.json'))
    s=f['s']; sk=SINK_MODEL.get(site,f['sink'])
    t0=M2[TPLI[site]]['tl']
    sites[site]=dict(yaw=f['yaw'],scale=round(s,4),sink=round(sk*s,4),dx=round(f['ox'],4),dz=round(f['oz'],4),iou=f['iou'],outside=f.get('outside'))
    for key,v in M2.items():
        if v['site']!=site: continue
        hexes[key]=dict(site=site,dx=round(f['ox']+(v['tl'][0]-t0[0])/R,4),dz=round(f['oz']+(v['tl'][1]-t0[1])/R,4))
old['_notes']['fit']=("yaw/scale/posizione massimizzano la sovrapposizione (iou) tra la sagoma del modello come la vede la telecamera iniziale "
 "(pitch 55°: v = z - 0.70·y) e la sagoma del disegno, penalizzando la parte della pianta del modello (vista dall'alto) che esce dal disegno "
 "(outside); l'orientamento di partenza è scelto a occhio confrontando la struttura (scale, ingressi, torri). Lo stesso disegno è ritrovato su "
 "ogni tessera con template matching: `hexes` dà la posizione per tessera|direzione; `sites` i valori comuni e la posizione predefinita.")
old['sites']=sites; old['hexes']=hexes
json.dump(old,open(p,'w'),indent=1,ensure_ascii=False)
