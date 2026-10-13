import sys,json,numpy as np
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from fit import *
from final import CH
K=0.70; LAM=float(__import__('os').environ.get('LAM','1.0'))
SINK={'tomb':0.015}
def score(mo,mt,D,s,ox,oz):
    a=shift_scale(mo,s,ox,oz); b=shift_scale(mt,s,ox,oz)
    out=np.logical_and(b,~D).sum()/max(b.sum(),1)
    return iou(a,D)-LAM*out
out={}
for site in sys.argv[1:]:
    c,w=CH[site]; sk=SINK.get(site,0.004)
    _,D=drawing(site); Ad=D.sum(); ys,xs=np.nonzero(D); cd=np.array([xs.mean(),ys.mean()])
    best=(-9,)
    for yaw in np.arange(c-w,c+w+0.1,2.5):
        mo=rend(site,yaw,K,1.0,0,0,sk); mt=rend(site,yaw,0.0,1.0,0,0,sk)
        s0=np.sqrt(Ad/max(mo.sum(),1))
        for ds in (0.8,0.85,0.9,0.95,1.0,1.05):
            ms=shift_scale(mo,s0*ds,0,0); yy,xx=np.nonzero(ms); o=(cd-np.array([xx.mean(),yy.mean()]))/P
            for ex in (-0.06,-0.03,0,0.03,0.06):
                for ez in (-0.09,-0.06,-0.03,0,0.03):
                    v=score(mo,mt,D,s0*ds,o[0]+ex,o[1]+ez)
                    if v>best[0]: best=(v,yaw,s0*ds,o[0]+ex,o[1]+ez)
    for step in (1.0,0.5):
        sc0,yaw,s,ox,oz=best
        for dy in (-step,0,step):
            mo=rend(site,yaw+dy,K,1.0,0,0,sk); mt=rend(site,yaw+dy,0.0,1.0,0,0,sk)
            for ds in (0.98,1.0,1.02):
                for ex in (-0.015,0,0.015):
                    for ez in (-0.015,0,0.015):
                        v=score(mo,mt,D,s*ds,ox+ex,oz+ez)
                        if v>best[0]: best=(v,yaw+dy,s*ds,ox+ex,oz+ez)
    sc0,yaw,s,ox,oz=best
    mo=rend(site,yaw,K,1.0,0,0,sk); mt=rend(site,yaw,0.0,1.0,0,0,sk)
    a=shift_scale(mo,s,ox,oz); b=shift_scale(mt,s,ox,oz)
    out=dict(iou=round(float(iou(a,D)),3),outside=round(float(np.logical_and(b,~D).sum()/b.sum()),3),yaw=round(float(yaw),1),s=round(float(s),4),ox=round(float(ox),4),oz=round(float(oz),4),sink=sk,k=K)
    print(site,out)
    json.dump(out,open(f'/tmp/site_calib/fin_{site}.json','w'))
