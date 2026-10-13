import json,numpy as np,sys,cv2
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from fit import proj, load
PP=100; HH=1.2; NN=int(2*HH*PP)
d=json.load(open('data/site_minis.json'))
def foot(site,dx,dz):
    v=d['sites'][site]; V,F,C=load(site)
    x,y,z=proj(site,v['yaw'],0.7,v['scale'],dx,dz,v['sink'])
    pts=(np.stack([(x+HH)*PP,(z+HH)*PP],1)*4).astype(np.int32)
    m=np.zeros((NN,NN),np.uint8)
    for f in F:
        if y[f].max()>0.03: cv2.fillConvexPoly(m,pts[f],1,shift=2)
    return m
def disc(cx,cz,r):
    m=np.zeros((NN,NN),np.uint8); cv2.circle(m,(int((cx+HH)*PP),int((cz+HH)*PP)),int(r*PP),1,-1); return m
r=0.4*0.62; step=2*r+0.03
res={}
for key,h in d['hexes'].items():
    fm=foot(h['site'],h['dx'],h['dz'])
    best=None
    for z in np.arange(0.50,0.90,0.02):
        worst=0
        for x in (-step,0,step,0.24-step/2,0.24+step/2):
            dm=disc(x,z-abs(x)*0.25,r); worst=max(worst,(dm&fm).sum()/dm.sum())
        if worst<0.04: best=z; break
    if best is None: best=0.88
    res[key]=round(float(best),2)
    print(key,h['site'],res[key])
json.dump(res,open('/tmp/site_calib/front.json','w'))
