import json, math, sys
from PIL import Image, ImageDraw
R=394; CX=1024; CY=985
DIRS = {"center": (0, 0), "0": (-1, 0), "180": (1, 0), "60": (-0.5, 1.5), "120": (0.5, 1.5), "240": (0.5, -1.5), "300": (-0.5, -1.5)}
S=['village','monastery','keep','mage_tower','dungeon','tomb','ruins','camp','maze','labyrinth','pyramid','ziggurat']
d=json.load(open('data/tiles.json'))['tiles']
inst=[]
for k,v in d.items():
  for dr,h in v['hexes'].items():
    if h.get('site') in S: inst.append((k,dr,h['site'],v['img']))
def crop(img,dr,scale=1.0):
  dx,dy=DIRS[dr]; cx=CX+dx*3**0.5*R; cy=CY+dy*R
  r=R*scale
  return img.crop((int(cx-r),int(cy-r),int(cx+r),int(cy+r)))
if __name__=='__main__':
  only=sys.argv[1] if len(sys.argv)>1 else None
  sel=[i for i in inst if not only or i[2]==only]
  T=220; cols=6; rows=(len(sel)+cols-1)//cols
  sheet=Image.new('RGB',(cols*T,rows*(T+14)),'white'); dd=ImageDraw.Draw(sheet)
  for n,(k,dr,s,img) in enumerate(sel):
    im=Image.open(img).convert('RGB'); c=crop(im,dr).resize((T,T))
    x=(n%cols)*T; y=(n//cols)*(T+14)
    sheet.paste(c,(x,y+14)); dd.text((x+2,y+1),f'{k} {dr} {s}',fill='black')
  sheet.save(sys.argv[2] if len(sys.argv)>2 else '/tmp/site_calib/sheet.png')
