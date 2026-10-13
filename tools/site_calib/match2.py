## Locate each site's stamp in every instance (fixed scale). Output: per instance, template top-left
## in tile-pixel offset relative to the hex centre; plus template rgb/mask saved per site.
import sys, json, numpy as np, cv2
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from crops import inst, R, CX, CY, DIRS
from match import template, TPL
M=1.35
out={}
tiles={}
for site in TPL:
    trgb,tm,_=template(site)
    sc={'ruins':0.545,'maze':0.56}.get(site,1.0)
    trgb=cv2.resize(trgb,None,fx=sc,fy=sc,interpolation=cv2.INTER_AREA)
    tm=(cv2.resize(tm,(trgb.shape[1],trgb.shape[0]),interpolation=cv2.INTER_AREA)>128).astype(np.uint8)*255
    cv2.imwrite(f'/tmp/site_calib/tpl_{site}.png',np.dstack([trgb,tm]))
    for k,dr,s,img in inst:
        if s!=site: continue
        if img not in tiles: tiles[img]=cv2.imread(img)
        T=tiles[img]
        dx,dy=DIRS[dr]; cx=CX+dx*3**0.5*R; cy=CY+dy*R
        r=int(R*M); x0=int(cx)-r; y0=int(cy)-r
        pad=cv2.copyMakeBorder(T,r,r,r,r,cv2.BORDER_CONSTANT,0)
        c=pad[y0+r:y0+3*r,x0+r:x0+3*r]
        F=0.5
        cs=cv2.resize(c,None,fx=F,fy=F,interpolation=cv2.INTER_AREA)
        ts=cv2.resize(trgb,None,fx=F,fy=F,interpolation=cv2.INTER_AREA)
        ms=cv2.resize(tm,(ts.shape[1],ts.shape[0]),interpolation=cv2.INTER_NEAREST)
        rr=cv2.matchTemplate(cs,ts,cv2.TM_CCORR_NORMED,mask=cv2.merge([ms]*3)); rr[~np.isfinite(rr)]=-1
        _,mx,_,loc=cv2.minMaxLoc(rr)
        # refine at full res around loc
        lx,ly=int(loc[0]/F),int(loc[1]/F)
        sx0,sy0=max(0,lx-4),max(0,ly-4)
        sub=c[sy0:ly+4+trgb.shape[0],sx0:lx+4+trgb.shape[1]]
        rr=cv2.matchTemplate(sub,trgb,cv2.TM_CCORR_NORMED,mask=cv2.merge([tm]*3)); rr[~np.isfinite(rr)]=-1
        _,mx,_,loc=cv2.minMaxLoc(rr)
        px,py=sx0+loc[0],sy0+loc[1]
        # template top-left relative to hex centre, in tile px
        out[f'{k}|{dr}']=dict(site=site,score=round(float(mx),4),tl=[px-r+(cx-int(cx))*0, py-r])
        print(k,dr,site,round(mx,4),px-r,py-r)
json.dump(out,open('/tmp/site_calib/match2.json','w'),indent=1)
