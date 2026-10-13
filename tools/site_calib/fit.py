import sys, json, numpy as np, cv2
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from rast import load
R=394.0; P=80; H=1.5; N=int(2*H*P)
M2=json.load(open('/tmp/site_calib/match2.json'))
TPLI={'village':'c01|180','monastery':'c05|240','keep':'c17|180','mage_tower':'c11|center','dungeon':'c07|120',
 'tomb':'k01|240','ruins':'c11|0','camp':'k09|120','maze':'c12|60','labyrinth':'k09|300','pyramid':'k12|180','ziggurat':'c17|60'}

def drawing(site, key=None):
    key=key or TPLI[site]
    t=cv2.imread(f'/tmp/site_calib/tpl_{site}.png',cv2.IMREAD_UNCHANGED)
    tl=M2[key]['tl']
    # place into frame: hex-unit (x,z) -> pixel (x+H)*P
    f=P/R
    A=np.float32([[f,0,(tl[0]/R+H)*P],[0,f,(tl[1]/R+H)*P]])
    rgb=cv2.warpAffine(t[:,:,:3],A,(N,N),flags=cv2.INTER_AREA)
    m=cv2.warpAffine(t[:,:,3],A,(N,N),flags=cv2.INTER_LINEAR)
    return rgb,(m>128)

def proj(site,yaw,k,s=1.0,ox=0.0,oz=0.0,sink=0.0):
    V,F,C=load(site)
    lo=V.min(0);hi=V.max(0);c=(lo+hi)/2
    Pm=(V-[c[0],lo[1],c[2]])*s
    a=np.radians(yaw);ca,sa=np.cos(a),np.sin(a)
    x=Pm[:,0]*ca+Pm[:,2]*sa+ox; z=-Pm[:,0]*sa+Pm[:,2]*ca+oz; y=Pm[:,1]-sink
    return x,y,z

def rend(site,yaw,k,s=1.0,ox=0.0,oz=0.0,sink=0.0,colour=False):
    V,F,C=load(site)
    x,y,z=proj(site,yaw,k,s,ox,oz,sink)
    u=(x+H)*P; v=(z-k*y+H)*P
    pts=(np.stack([u,v],1)*4).astype(np.int32)
    m=np.zeros((N,N),np.uint8)
    keep=y[F].max(1)>0
    if not colour:
        for f in F[keep]:
            cv2.fillConvexPoly(m,pts[f],255,shift=2)
        return m>0
    img=np.zeros((N,N,3),np.uint8)
    depth=(y+k*z)[F].mean(1)
    for i in np.argsort(depth):
        if not keep[i]: continue
        f=F[i]
        cv2.fillConvexPoly(img,pts[f],C[f].mean(0)[::-1].tolist(),shift=2)
        cv2.fillConvexPoly(m,pts[f],255,shift=2)
    return img,m>0

def iou(a,b):
    i=np.logical_and(a,b).sum(); u=np.logical_or(a,b).sum()
    return i/max(u,1)

def shift_scale(m,s,ox,oz):
    # m rendered at s=1, offset 0 (anchor at frame centre). apply scale about centre + offset (hex units)
    c=H*P
    A=np.float32([[s,0,c*(1-s)+ox*P],[0,s,c*(1-s)+oz*P]])
    return cv2.warpAffine(m.astype(np.uint8)*255,A,(N,N),flags=cv2.INTER_LINEAR)>127

def fit(site, yaws=range(0,360,5), ks=(0.3,0.5,0.7,0.9,1.1)):
    Drgb,D=drawing(site)
    Ad=D.sum(); ys,xs=np.nonzero(D); cd=np.array([xs.mean(),ys.mean()])
    res=[]
    for k in ks:
        for yaw in yaws:
            m=rend(site,yaw,k)
            Am=m.sum(); s=np.sqrt(Ad/Am)
            best=(-1,)
            for ds in (0.88,0.94,1.0,1.06,1.12):
                ms=shift_scale(m,s*ds,0,0)
                yy,xx=np.nonzero(ms); cm=np.array([xx.mean(),yy.mean()])
                o=(cd-cm)/P
                for ex in (-0.04,0,0.04):
                    for ez in (-0.04,0,0.04):
                        sc=iou(shift_scale(m,s*ds,o[0]+ex,o[1]+ez),D)
                        if sc>best[0]: best=(sc,s*ds,o[0]+ex,o[1]+ez)
            res.append((best[0],yaw,k,best[1],best[2],best[3]))
    res.sort(reverse=True)
    return res

def refine(site,c):
    Drgb,D=drawing(site)
    _,yaw,k,s,ox,oz=c
    best=c
    for it in range(3):
        step=[2.0,1.0,0.5][it]
        for dy in (-step,0,step):
          for dk in (-0.1*step/2,0,0.1*step/2):
            m=rend(site,best[1]+dy,best[2]+dk)
            for ds in (0.97,1.0,1.03):
              for ex in (-0.02,0,0.02):
                for ez in (-0.02,0,0.02):
                    sc=iou(shift_scale(m,best[3]*ds,best[4]+ex,best[5]+ez),D)
                    if sc>best[0]+1e-6: best=(sc,best[1]+dy,best[2]+dk,best[3]*ds,best[4]+ex,best[5]+ez)
    return best

def colour_score(site,c):
    Drgb,D=drawing(site)
    _,yaw,k,s,ox,oz=c
    img,m=rend(site,yaw,k,s,ox,oz,colour=True)
    g1=cv2.GaussianBlur(cv2.cvtColor(img,cv2.COLOR_BGR2GRAY).astype(np.float32),(0,0),2)
    g2=cv2.GaussianBlur(cv2.cvtColor(Drgb,cv2.COLOR_BGR2GRAY).astype(np.float32),(0,0),2)
    r=np.logical_and(m,D)
    a=g1[r]-g1[r].mean(); b=g2[r]-g2[r].mean()
    return float((a*b).sum()/np.sqrt((a*a).sum()*(b*b).sum()+1e-6))

if __name__=='__main__':
    out={}
    for site in sys.argv[1:]:
        res=fit(site)
        # dedupe candidates: keep top by distinct yaw clusters
        cands=[]
        for r in res:
            if all(min(abs(r[1]-c[1]),360-abs(r[1]-c[1]))>15 or abs(r[2]-c[2])>0.25 for c in cands):
                cands.append(r)
            if len(cands)>=6: break
        scored=[]
        for c in cands:
            cs=colour_score(site,c); scored.append((c[0]+0.5*cs,cs,c))
            print(site,'cand',[round(v,3) for v in c],'col',round(cs,3))
        scored.sort(reverse=True)
        b=refine(site,scored[0][2])
        print(site,'BEST',[round(v,3) for v in b])
        out[site]=dict(iou=b[0],yaw=b[1],k=b[2],s=b[3],ox=b[4],oz=b[5],cands=[[round(v,3) for v in x[2]]+[round(x[1],3)] for x in scored])
        json.dump(out[site],open(f'/tmp/site_calib/fit_{site}.json','w'),indent=1)
