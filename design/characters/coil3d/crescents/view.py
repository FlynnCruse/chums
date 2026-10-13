"""Side-by-side viewer: for a frame, full truth | tiles, then zooms (head, leftmost cusp) of both."""
import sys, numpy as np
from PIL import Image, ImageDraw
from coilpaint import *
import tiles4 as TL
def render_pair(world, S=4, zs=5, extra=None, kw=None):
    q=catmull(world,5); head=q[-1,:2]+np.array([CX,CY]); left=q[np.argmin(q[:,0]),:2]+np.array([CX,CY])
    tr=to_img(truth(world,S=S),S); tl=to_img(TL.tiles4(world,S=S,**(kw or {}))[0],S)
    crops=[(int(head[0])-35,int(head[1])-25,70,50),(int(left[0])-15,int(left[1])-25,70,50)]+(extra or [])
    tw,th=W*2,HH*2
    out=Image.new('RGB',(2*(tw+8)+8,th+len(crops)*(50*zs+8)+16),(24,24,26)); dr=ImageDraw.Draw(out)
    for c,(label,im) in enumerate((('truth',tr),('tiles',tl))):
        x0=8+c*(tw+8); out.paste(im,(x0,8)); dr.text((x0+4,th+2),label,fill=(220,220,220))
        for j,(x,y,w,h) in enumerate(crops):
            z=im.crop((x*2,y*2,(x+w)*2,(y+h)*2)).resize((w*zs,h*zs),Image.LANCZOS); out.paste(z,(x0,8+th+8+j*(50*zs+8)))
    return out
if __name__=='__main__':
    T,Wd=load_dump(sys.argv[1]); tt=float(sys.argv[2]); out=sys.argv[3]
    render_pair(Wd[int(round(tt*60))]).save(out); print(out)
