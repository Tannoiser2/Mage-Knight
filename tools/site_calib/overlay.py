import sys,json,numpy as np,cv2
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from fit import *
def tile_frame(key):
    from crops import inst, CX, CY, DIRS
    k,dr=key.split('|')
    img=[i[3] for i in inst if i[0]==k and i[1]==dr][0]
    T=cv2.imread(''+img)
    dx,dy=DIRS[dr]; cx=CX+dx*3**0.5*R; cy=CY+dy*R
    f=P/R
    A=np.float32([[f,0,(H-cx/R)*P],[0,f,(H-cy/R)*P]])
    return cv2.warpAffine(T,A,(N,N),flags=cv2.INTER_AREA)
def panel(site,p,key=None,label=''):
    key=key or TPLI[site]
    bg=tile_frame(key)
    _,D=drawing(site,key)
    img,m=rend(site,p['yaw'],p['k'],p['s'],p['ox'],p['oz'],p.get('sink',0),colour=True)
    a=bg.copy(); b=bg.copy(); b[m]=img[m]
    for o in (a,b):
        cs,_=cv2.findContours(D.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE); cv2.drawContours(o,cs,-1,(0,255,0),1)
        cs,_=cv2.findContours(m.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE); cv2.drawContours(o,cs,-1,(0,0,255),1)
    r=np.hstack([a,b]); cv2.putText(r,label or site,(3,14),0,0.45,(255,255,255),1); return r
if __name__=='__main__':
    rows=[]
    for site in sys.argv[2:]:
        p=json.load(open(f'fit_{site}.json')); rows.append(panel(site,p,label=f"{site} y{p['yaw']:.0f} k{p['k']:.2f} s{p['s']:.2f} iou{p['iou']:.2f}"))
    cols=2
    while len(rows)%cols: rows.append(np.zeros_like(rows[0]))
    cv2.imwrite(sys.argv[1],np.vstack([np.hstack(rows[i:i+cols]) for i in range(0,len(rows),cols)]))
