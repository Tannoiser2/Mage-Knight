import sys,glob,os,cv2,numpy as np
d=sys.argv[1]; outp=sys.argv[2]; filt=sys.argv[3] if len(sys.argv)>3 else ''
names=sorted(set(os.path.basename(f)[:-8] for f in glob.glob(d+'/*_top.png') if filt in f))
rows=[]
for n in names:
    a=cv2.imread(f'{d}/{n}_top.png'); b=cv2.imread(f'{d}/{n}_obl.png')
    h,w=a.shape[:2]; c=lambda im: cv2.resize(im[h//2-260:h//2+260, w//2-300:w//2+300],(360,312))
    r=np.hstack([c(a),c(b)]); cv2.putText(r,n,(4,16),0,0.5,(255,255,255),1); rows.append(r)
cols=2
while len(rows)%cols: rows.append(np.zeros_like(rows[0]))
cv2.imwrite(outp,np.vstack([np.hstack(rows[i:i+cols]) for i in range(0,len(rows),cols)]))
