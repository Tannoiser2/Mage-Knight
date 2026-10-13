import numpy as np, trimesh, cv2
from functools import lru_cache
@lru_cache(None)
def load(site):
    s = trimesh.load(f'assets/miniatures/site_{site}.glb')
    geoms=[]
    for name in s.graph.nodes_geometry:
        T, gname = s.graph[name]
        g = s.geometry[gname].copy(); g.apply_transform(T)
        try:
            col = g.visual.to_color().vertex_colors[:, :3].astype(np.float32)
        except Exception:
            col = np.full((len(g.vertices),3),160,np.float32)
        geoms.append((np.asarray(g.vertices,np.float64), np.asarray(g.faces), col))
    V=np.concatenate([g[0] for g in geoms]); off=0; F=[]; C=[]
    for v,f,c in geoms:
        F.append(f+off); off+=len(v); C.append(c)
    return V, np.concatenate(F), np.concatenate(C)

def project(V, yaw, s, k, dx=0, dz=0, sink=0):
    """model native coords -> image plane (hex units): u=x, v=z-k*y. Model anchored at bbox centre xz, min y."""
    lo=V.min(0); hi=V.max(0); c=(lo+hi)/2
    P=(V-[c[0],lo[1],c[2]])*s
    a=np.radians(yaw); ca,sa=np.cos(a),np.sin(a)
    # Godot rotation about Y by +yaw: x' = x cos + z sin ; z' = -x sin + z cos
    x=P[:,0]*ca+P[:,2]*sa; z=-P[:,0]*sa+P[:,2]*ca; y=P[:,1]-sink
    return x+dx, y, z+dz

def render(site, yaw, s, k, dx=0, dz=0, sink=0, size=400, half=1.0, colour=True, clip_ground=True):
    V,F,C=load(site)
    x,y,z=project(V,yaw,s,k,dx,dz,sink)
    u=(x/half+1)*size/2; v=((z-k*y)/half+1)*size/2
    depth=(z+y*1.0)[F].mean(1)
    ok=np.ones(len(F),bool)
    if clip_ground: ok=(y[F].max(1)>0)  # triangles fully below ground hidden
    order=np.argsort(depth)
    img=np.zeros((size,size,3),np.uint8); m=np.zeros((size,size),np.uint8)
    pts=np.stack([u,v],1)
    # simple lambert shading
    for i in order:
        if not ok[i]: continue
        f=F[i]
        p=(pts[f]*4).astype(np.int32)
        col=C[f].mean(0)
        if colour:
            cv2.fillConvexPoly(img,p,col.tolist(),lineType=cv2.LINE_AA,shift=2)
        cv2.fillConvexPoly(m,p,255,shift=2)
    return img,m

def front(site, size=200, half=0.8):
    V,F,C=load(site)
    lo=V.min(0);hi=V.max(0);c=(lo+hi)/2
    u=((V[:,0]-c[0])/half+1)*size/2; v=((-(V[:,1]-c[1]))/half+1)*size/2
    img=np.zeros((size,size,3),np.uint8)
    pts=np.stack([u,v],1)
    for i in np.argsort(V[F][:,:,2].mean(1)):
        cv2.fillConvexPoly(img,(pts[F[i]]*4).astype(np.int32),C[F[i]].mean(0).tolist(),shift=2)
    return img
