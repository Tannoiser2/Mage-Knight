import sys, json, numpy as np, cv2
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from crops import inst, crop, R
from PIL import Image
D='/tmp/site_calib/m/'
TPL={'village':'c01_180','monastery':'c05_240','keep':'c17_180','mage_tower':'c11_center','dungeon':'c07_120',
 'tomb':'k01_240','ruins':'ref','camp':'k09_120','maze':'ref','labyrinth':'k09_300','pyramid':'k12_180','ziggurat':'c17_60'}
F=0.5  # work at half resolution
def template(site):
    src=TPL[site]
    if src=='ref':
        im=cv2.imread(f'meshy/riferimenti/site_{site}.png',cv2.IMREAD_UNCHANGED)
        rgb=im[:,:,:3]; m=im[:,:,3]
    else:
        rgb=cv2.imread(D+src+'_crop.png'); m=cv2.imread(D+src+'_mask.png',0)
    m=(m>128).astype(np.uint8)*255
    m=cv2.morphologyEx(m,cv2.MORPH_OPEN,np.ones((5,5),np.uint8))
    x,y,w,h=cv2.boundingRect(m)
    return rgb[y:y+h,x:x+w], m[y:y+h,x:x+w], (x,y)
if __name__=='__main__':
    res={}
    for site in TPL:
        trgb,tm,(tx,ty)=template(site)
        scales=np.arange(0.40,0.62,0.01) if TPL[site]=='ref' else np.arange(0.92,1.085,0.01)
        for k,dr,s,img in inst:
            if s!=site: continue
            c=cv2.imread(D+f'{k}_{dr}_crop.png'); c=cv2.resize(c,None,fx=F,fy=F,interpolation=cv2.INTER_AREA)
            best=(-9,)
            for sc in scales:
                t=cv2.resize(trgb,None,fx=sc*F,fy=sc*F,interpolation=cv2.INTER_AREA)
                mm=cv2.resize(tm,(t.shape[1],t.shape[0]),interpolation=cv2.INTER_NEAREST)
                if t.shape[0]>=c.shape[0] or t.shape[1]>=c.shape[1]: continue
                r=cv2.matchTemplate(c,t,cv2.TM_CCORR_NORMED,mask=cv2.merge([mm,mm,mm]))
                r[~np.isfinite(r)]=-1
                _,mx,_,loc=cv2.minMaxLoc(r)
                if mx>best[0]: best=(mx,sc,loc,t.shape)
            mx,sc,loc,sh=best
            # template bbox in crop pixels (full res); crop centre = (R,R)
            x0=loc[0]/F; y0=loc[1]/F; w=sh[1]/F; h=sh[0]/F
            res[f'{k}|{dr}']=dict(site=site,score=round(mx,4),scale=round(sc,3),box=[x0,y0,w,h])
            print(k,dr,site,round(mx,4),round(sc,3),[round(v) for v in (x0,y0,w,h)])
    json.dump(res,open('/tmp/site_calib/match.json','w'),indent=1)
