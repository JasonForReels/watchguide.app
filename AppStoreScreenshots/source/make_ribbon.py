# One continuous light streak across the 6-slide panorama, sliced per slide.
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops
S=4; W,H=7920//S,2868//S
cols=[(150,120,255),(255,122,85),(255,211,166)]
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def col(x):
    t=(x/W)*2
    return lerp(cols[0],cols[1],t) if t<1 else lerp(cols[1],cols[2],t-1)
def y(x,k):
    X=x*S
    return (1150 + 300*math.sin(2*math.pi*X/3600+0.6) + 100*math.sin(2*math.pi*X/1450+k) + k*50)/S
glow=Image.new('RGB',(W,H)); core=Image.new('RGB',(W,H))
dg=ImageDraw.Draw(glow); dc=ImageDraw.Draw(core)
for k,(wg,wc) in enumerate([(24,3),(12,2),(7,1)]):
    pts=[(x,y(x,k*1.3)) for x in range(-5,W+6)]
    for i in range(len(pts)-1):
        c=col(max(0,min(W-1,pts[i][0])))
        dg.line([pts[i],pts[i+1]],fill=c,width=wg)
        dc.line([pts[i],pts[i+1]],fill=tuple(min(255,int(v*.6+110)) for v in c),width=wc)
out=ImageChops.add(glow.filter(ImageFilter.GaussianBlur(22)),core.filter(ImageFilter.GaussianBlur(1.2))).resize((7920,2868),Image.BICUBIC)
for i in range(6): out.crop((i*1320,0,(i+1)*1320,2868)).save(f'ribbon_{i+1}.png')
