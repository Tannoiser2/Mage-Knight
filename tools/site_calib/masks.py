import sys, os, numpy as np, cv2, math
sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from crops import inst, crop, R
from PIL import Image, ImageDraw
from rembg import remove, new_session
sess=new_session('isnet-general-use' if len(sys.argv)>1 and sys.argv[1]=='isnet' else 'u2net')
os.makedirs('/tmp/site_calib/m',exist_ok=True)
for k,dr,s,img in inst:
    im=Image.open(img).convert('RGB'); c=crop(im,dr,1.0)
    hexm=Image.new('L',c.size,0)
    pts=[(c.width/2+R*0.97*math.cos(math.radians(60*i-90)),c.height/2+R*0.97*math.sin(math.radians(60*i-90))) for i in range(6)]
    ImageDraw.Draw(hexm).polygon(pts,fill=255)
    c.save(f'/tmp/site_calib/m/{k}_{dr}_crop.png')
    out=remove(c,session=sess,only_mask=True)
    a=np.minimum(np.array(out),np.array(hexm))
    cv2.imwrite(f'/tmp/site_calib/m/{k}_{dr}_mask.png',a)
    print(k,dr,s,(a>128).mean())
