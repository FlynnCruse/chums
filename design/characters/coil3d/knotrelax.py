"""SONO-style relaxation: an open trefoil tightened to 2R clearance at length L (ideal-knot style)."""
import numpy as np, tube3d as T, rod
R=T.R
def relax(P, L, R, excl, iters=4000, shrink=0.996, seed=0):
    P=P.copy(); n=len(P); seg=T.length(P)/(n-1); target=L/(n-1)
    iu=np.triu_indices(n,1)
    s=np.arange(n)*seg
    far=(np.abs(s[:,None]-s[None])>excl)[iu]
    I,J=iu[0][far],iu[1][far]
    for it in range(iters):
        # overlaps -> push apart to 2R (+1%)
        d=P[J]-P[I]; dist=np.linalg.norm(d,axis=1); lim=2*R*1.02
        hit=dist<lim
        if hit.any():
            push=d[hit]/dist[hit][:,None]*(lim-dist[hit])[:,None]*0.5
            np.add.at(P,I[hit],-push); np.add.at(P,J[hit],push)
        # restore segment lengths (a few passes)
        for _ in range(3):
            dd=np.diff(P,axis=0); ln=np.linalg.norm(dd,axis=1); cor=dd*((ln-seg)/np.maximum(ln,1e-9))[:,None]*0.5
            P[:-1]+=cor; P[1:]-=cor
        # light smoothing of curvature (keeps it pretty)
        Q=P.copy(); Q[1:-1]=P[1:-1]+0.05*(P[:-2]+P[2:]-2*P[1:-1]); P=Q
        if seg>target: seg=max(target,seg*shrink)
        # recompute far mask arc-length based on seg
    return P
t0=0.95; zk=3.2
t=np.linspace(t0,2*np.pi-t0,400)
P0=np.stack([np.sin(t)+2*np.sin(2*t),np.cos(t)-2*np.cos(2*t),-zk*np.sin(3*t)],1)
P0=P0*(1.45*T.L/T.length(P0)); P0,_=T.resample(P0,400)
radii=np.full(400,R)
print('start len',round(T.length(P0),1),'minsep',round(rod.min_sep(P0,radii,4.5*R),3))
P=relax(P0,T.L,R,4.5*R)
P,_=T.resample(P,400)
print('relaxed len',round(T.length(P),1),'minsep',round(rod.min_sep(P,radii,4.5*R),3),'extent',np.ptp(P,axis=0).round(0))
np.save('knot_relaxed.npy',P)
# with the head swell 1.4 at the tip, is the head end clear?
from slicer import radius_profile
rp=radius_profile(np.linspace(0,1,400),1.4)
print('with swell 1.4: minsep',round(rod.min_sep(P,rp,4.5*R),3))
