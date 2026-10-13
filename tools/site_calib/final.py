import sys,json,numpy as np
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from fit import *
K=0.70
# yaw centre chosen by eye from yaw_<site>.png (structure), window searched by silhouette IoU
CH={'village':(180,30),'monastery':(315,20),'keep':(315,20),'mage_tower':(315,45),'dungeon':(45,20),
    'tomb':(45,20),'ruins':(330,30),'camp':(30,25),'maze':(180,25),'labyrinth':(15,40),'pyramid':(315,15),'ziggurat':(315,15)}
SINK={'tomb':0.015}   # model units (native), below which geometry is underground
if __name__=='__main__':
  out={}
  for site in (sys.argv[1:] or CH):
      c,w=CH[site]; sk=SINK.get(site,0.004)
      _,D=drawing(site); Ad=D.sum(); ys,xs=np.nonzero(D); cd=np.array([xs.mean(),ys.mean()])
      best=(-1,)
      for yaw in np.arange(c-w,c+w+0.1,2.5):
          # sink is in native units: scale-dependent; iterate scale twice
          s=1.2
          for _ in range(2):
              m=rend(site,yaw,K,1.0,0,0,sk)  # sink at s=1 (native units) -> clipping identical under scaling
              s=np.sqrt(Ad/max(m.sum(),1))
          for ds in (0.9,0.95,1.0,1.05,1.1):
              ms=shift_scale(m,s*ds,0,0); yy,xx=np.nonzero(ms); o=(cd-np.array([xx.mean(),yy.mean()]))/P
              for ex in (-0.03,0,0.03):
                  for ez in (-0.03,0,0.03):
                      sc=iou(shift_scale(m,s*ds,o[0]+ex,o[1]+ez),D)
                      if sc>best[0]: best=(sc,yaw,s*ds,o[0]+ex,o[1]+ez)
      # fine refine
      sc0,yaw,s,ox,oz=best
      for step in (1.0,0.5):
          for dy in (-step,0,step):
              m=rend(site,yaw+dy,K,1.0,0,0,sk)
              for ds in (0.98,1.0,1.02):
                  for ex in (-0.015,0,0.015):
                      for ez in (-0.015,0,0.015):
                          v=iou(shift_scale(m,s*ds,ox+ex,oz+ez),D)
                          if v>best[0]: best=(v,yaw+dy,s*ds,ox+ex,oz+ez)
          sc0,yaw,s,ox,oz=best
      # NB: shift_scale scales the s=1 render about the frame centre, where the anchor sits -> anchor at (ox,oz)
      out[site]=dict(iou=round(best[0],3),yaw=round(yaw,1),s=round(s,4),ox=round(ox,4),oz=round(oz,4),sink=sk,k=K)
      print(site,out[site])
      json.dump(out[site],open(f'/tmp/site_calib/fin_{site}.json','w'))
