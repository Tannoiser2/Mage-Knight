import sys,json,numpy as np,cv2
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import fit as FT
from fit import *
from overlay import tile_frame
def shaded(site,yaw,k,s,ox,oz,sink=0,PP=160,HH=0.9,centre=None):
    V,F,C=load(site)
    x,y,z=proj(site,yaw,k,s,ox,oz,sink)
    W=np.stack([x,y,z],1)
    n=np.cross(W[F[:,1]]-W[F[:,0]],W[F[:,2]]-W[F[:,0]]); n/=np.linalg.norm(n,axis=1,keepdims=True)+1e-9
    L=np.array([-0.4,0.8,0.45]); L/=np.linalg.norm(L)
    sh=np.clip(np.abs(n@L),0,1)*0.75+0.35
    cx,cz=centre if centre is not None else (ox,oz)
    u=(x-cx+HH)*PP; v=(z-k*y-cz+HH*0.9)*PP
    NN=int(2*HH*PP)
    pts=(np.stack([u,v],1)*4).astype(np.int32)
    img=np.full((NN,NN,3),40,np.uint8)
    depth=(y+k*z)[F].mean(1)
    for i in np.argsort(depth):
        if y[F[i]].max()<=0: continue
        col=np.clip(C[F[i]].mean(0)[::-1]*sh[i],0,255)
        cv2.fillConvexPoly(img,pts[F[i]],col.tolist(),shift=2)
    return img
def drawing_view(site,ox,oz,key=None,PP=160,HH=0.9):
    key=key or TPLI[site]
    from crops import inst, CX, CY, DIRS
    k,dr=key.split('|'); img=[i[3] for i in inst if i[0]==k and i[1]==dr][0]
    T=cv2.imread(''+img)
    dx,dy=DIRS[dr]; hx=CX+dx*3**0.5*R; hy=CY+dy*R
    f=PP/R
    # pixel(u) = (X - ox + HH)*PP where X = (px-hx)/R
    A=np.float32([[f,0,(-hx/R-ox+HH)*PP],[0,f,(-hy/R-oz+HH*0.9)*PP]])
    NN=int(2*HH*PP)
    return cv2.warpAffine(T,A,(NN,NN),flags=cv2.INTER_AREA)
if __name__=='__main__':
    site=sys.argv[1]; yaws=[float(a) for a in sys.argv[2].split(',')] if len(sys.argv)>2 else list(range(0,360,45))
    K=0.70
    _,D=drawing(site); 
    ys,xs=np.nonzero(D); cd=np.array([xs.mean(),ys.mean()])/P-H
    tiles=[drawing_view(site,cd[0],cd[1])]
    for yaw in yaws:
        m=rend(site,yaw,K); s=np.sqrt(D.sum()/m.sum())
        ms=shift_scale(m,s,0,0); yy,xx=np.nonzero(ms); o=cd-(np.array([xx.mean(),yy.mean()])/P-H)
        img=shaded(site,yaw,K,s,o[0],o[1],centre=cd)
        tiles.append(img)
        cv2.putText(img,f'{yaw:.0f}',(4,18),0,0.6,(255,255,255),1)
    cv2.imwrite(f'yaw_{site}.png',np.hstack(tiles[:5]) if len(tiles)<=5 else np.vstack([np.hstack(tiles[:5]),np.hstack(tiles[5:]+[np.zeros_like(tiles[0])]*(10-len(tiles)))]))
