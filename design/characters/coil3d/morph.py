"""Bakes a change of shape A -> B as frames of a rope sim: pulled toward a blend of the two (each link's direction
turning, as a front or all at once), its length kept, its bends never tighter than the limit, its foot planted, and
its parts never closer than the tube's width. So it finds its own way round itself. Played back on the watch."""
import numpy as np, tube3d as T, rod
from shapes import R, L, NN, clear, rk, at
from trans import dirblend, weights
NS=96
SEGS=L/(NS-1)
KMAX=0.8*SEGS/R             # joint turn limit (bend radius >= ~1.25 R)
def iu_far(n,excl):
    I,J=np.triu_indices(n,1); m=(J-I)>excl; return I[m],J[m]
I,J=iu_far(NS,int(np.ceil(4.5*R/SEGS)))
ZB=1.5
def bend(X,k=0.5):
    d=np.diff(X,axis=0); t=d/np.linalg.norm(d,axis=1,keepdims=True)
    th=np.arccos(np.clip((t[:-1]*t[1:]).sum(1),-1,1))
    bad=np.where(th>KMAX)[0]+1
    if len(bad):
        mid=(X[bad-1]+X[bad+1])/2; X[bad]+=k*(mid-X[bad])*np.clip((th[bad-1]-KMAX)/KMAX*3,0.2,1)[:,None]
    return X
def project(X,pin,iters=30):
    for _ in range(iters):
        X[0]=pin
        X=bend(X,0.6); X=bend(X,0.6); X=bend(X,0.6)
        # collisions: parts that meet slide past each other mostly in depth (one in front of the other)
        dv=X[J]-X[I]; dist=np.linalg.norm(dv,axis=1); lim=2*R*1.04; hit=dist<lim
        if hit.any():
            dh=dv[hit]; sz=np.where(dh[:,2]>=0,1.0,-1.0)
            dirn=dh/np.maximum(dist[hit],1e-9)[:,None]+np.stack([0*sz,0*sz,ZB*sz],1)
            dirn/=np.linalg.norm(dirn,axis=1,keepdims=True)
            push=dirn*(lim-dist[hit])[:,None]*0.5
            wi=np.where(I[hit]==0,0,1.0)[:,None]
            np.add.at(X,I[hit],-push*wi); np.add.at(X,J[hit],push*(2-wi))
        # lengths
        for _k in range(2):
            dd=np.diff(X,axis=0); ln=np.linalg.norm(dd,axis=1); cor=dd*((ln-SEGS)/np.maximum(ln,1e-9))[:,None]*0.5
            X[:-1]+=cor; X[1:]-=cor
        X[0]=pin
    return X
def bake(A,B,mode,frames=160,settle=30,pull=0.07):
    A=at(A,NS); B=at(B,NS)
    X=A.copy(); out=[X.copy()]
    for f in range(1,frames+settle+1):
        p=min(1,f/frames); e=p*p*(3-2*p)
        tgt=dirblend(A,B,weights(NS-1,e,mode))
        X+=(tgt-X)*pull
        X=project(X,tgt[0])
        out.append(X.copy())
    K=np.array(out)
    return finish(K,A,B)
def finish(K,A,B,rounds=6,sigma=3.0,glide=16):
    """Make a baked change of shape smooth in time and still valid: glide the end exactly into B, then alternate a
    smoothing in time (ends held) with putting every frame back within its constraints, until both hold."""
    from scipy.ndimage import gaussian_filter1d
    K=K.copy(); n=len(K)
    for i in range(glide):
        w=(i+1)/glide; w=w*w*(3-2*w)
        K[n-glide+i]=K[n-glide+i]*(1-w)+B*w
    K[0]=A; K[-1]=B
    pad=int(4*sigma)+1
    for _ in range(rounds):
        Kp=np.concatenate([np.repeat(K[:1],pad,0),K,np.repeat(K[-1:],pad,0)])
        Kp=gaussian_filter1d(Kp,sigma,axis=0)[pad:-pad]
        for f in range(1,n-1):
            X=Kp[f].copy(); K[f]=project(X,X[0].copy(),iters=3)
        K[0]=A; K[-1]=B
    # last, a smoothing in time alone (the frames it averages are valid, so the result stays valid), as strong as it
    # can be while no part comes closer than the tube's width
    for sig in (3.0, 2.0, 1.0):
        pad2=int(4*sig)+1
        Kp=np.concatenate([np.repeat(K[:1],pad2,0),K,np.repeat(K[-1:],pad2,0)])
        Ks=gaussian_filter1d(Kp,sig,axis=0)[pad2:-pad2]; Ks[0]=A; Ks[-1]=B
        if min(clear(at(k)) for k in Ks[::3]) >= 0.98: return Ks
    return K
def stats(K,B):
    cl=min(clear(at(k)) for k in K); mk=max(rk(at(k)) for k in K)
    v=np.linalg.norm(np.diff(K,axis=0),axis=2).max(axis=1)        # fastest point per frame
    acc=np.linalg.norm(np.diff(K,2,axis=0),axis=2).max()
    err=np.linalg.norm(at(K[-1],NS)-at(B,NS),axis=1).max()
    return cl,mk,v.max(),acc,err
if __name__=='__main__':
    import sys
    lib=dict(np.load('lib.npz'))
    a,b=sys.argv[1],sys.argv[2]
    for mode in ('all','foot','head'):
        K=bake(lib[a],lib[b],mode)
        print('%s->%s %-4s clear %.2f  R*k %.2f  max step %.1f pt  max jerk %.1f  end error %.1f pt'%((a,b,mode)+stats(K,lib[b])))
