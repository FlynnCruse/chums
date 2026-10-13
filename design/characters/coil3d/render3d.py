import numpy as np
from PIL import Image, ImageDraw
from tube3d import *
def shade_n(u,N):
    x,y,z=N[...,0],N[...,1],N[...,2]
    F=np.stack([np.ones_like(x),x,y,z,x*y,x*z,y*z,x*x-y*y,3*z*z-1],-1)
    kn=len(ALB);f=np.clip(u,0,1)*(kn-1);k0=np.minimum(kn-2,f.astype(int));w=(f-k0)[...,None]
    alb=ALB[k0]*(1-w)+ALB[k0+1]*w
    return alb*(F@LIGHT)[...,None]+(F@SHEEN)[...,None]
def render(P,yaw=0.0,S=4,W=198,H=242,center=(99,138),ao=True,label=''):
    c,s=np.cos(yaw),np.sin(yaw);P=P@np.array([[c,0,s],[0,1,0],[-s,0,c]]).T
    n=len(P);u=np.linspace(0,1,n)
    # u along the albedo: the traced tube covers the first part; the head stays its end colour
    ua=np.clip(u*L/373.0,0,1)
    T=np.gradient(P,axis=0);T/=np.linalg.norm(T,axis=1,keepdims=True)
    img=np.zeros((H*S,W*S,3));zb=np.full((H*S,W*S),-1e9)
    yy,xx=np.mgrid[0:H*S,0:W*S].astype(float)
    X=xx/S-center[0];Y=yy/S-center[1]
    sarc=np.concatenate([[0],np.cumsum(np.linalg.norm(np.diff(P,axis=0),axis=1))])
    for i in range(n):
        p=P[i];r=R
        x0=int(max(0,(p[0]+center[0]-r-2)*S));x1=int(min(W*S,(p[0]+center[0]+r+2)*S));y0=int(max(0,(p[1]+center[1]-r-2)*S));y1=int(min(H*S,(p[1]+center[1]+r+2)*S))
        if x1<=x0 or y1<=y0: continue
        dx=X[y0:y1,x0:x1]-p[0];dy=Y[y0:y1,x0:x1]-p[1]
        # sphere sweep: each sample a sphere of radius R (the union is the tube); the tube's normal is the sphere's
        # normal with its component along the tube removed
        d2=dx*dx+dy*dy;m=d2<r*r
        if not m.any(): continue
        dz=np.sqrt(np.clip(r*r-d2,0,None));z=p[2]+dz
        Nraw=np.stack([dx,dy,dz],-1)/r
        t=T[i];Nt=Nraw-(Nraw@t)[...,None]*t;Nt/=np.linalg.norm(Nt,axis=-1,keepdims=True)+1e-9
        if i==0 or i==n-1: Nt=Nraw   # rounded ends
        zz=z+(Nraw@t)*0   # depth of the sphere surface
        zbuf=zb[y0:y1,x0:x1];win=m&(z>zbuf)
        if not win.any(): continue
        col=shade_n(np.full(win.sum(),ua[i]),Nt[win])
        if ao:
            far=np.abs(sarc-sarc[i])>3.5*R
            Q=P[far]
            if len(Q):
                pts=np.stack([dx[win]+p[0],dy[win]+p[1],z[win]],1)
                D=Q[None]-pts[:,None];dd=np.linalg.norm(D,axis=2)
                nd=(D*Nt[win][:,None]).sum(2)/np.maximum(dd,1e-6)
                occ=(np.clip(nd,0,1)*np.clip(1-(dd-R)/(1.8*R),0,1)**2).max(1)
                a=np.clip(occ,0,1)[:,None]
                col=col*(1-np.array([0.5,0.25,0.06])*a)*(1-0.3*a)
        sub=img[y0:y1,x0:x1];sub[win]=col;zbuf[win]=z[win]
    im=Image.fromarray((np.clip(img,0,1)*255).astype(np.uint8)).resize((W*2,H*2),Image.LANCZOS)
    if label: ImageDraw.Draw(im).text((8,8),label,fill=(255,255,255))
    # eyes
    return im
