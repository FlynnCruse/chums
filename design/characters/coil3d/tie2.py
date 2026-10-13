"""Bake the knot entry (tie.py), with the head finishing in front (toward you) and up so the face stays seen."""
import numpy as np, tube3d as T, rod
R=T.R; n=100; seg=T.L/(n-1)
def resample_n(P,m): Q,_=T.resample(P,m); return Q
def pbd_step(X, head_target, pin0, iters=12, excl_nodes=11, bend=0.08):
    n=len(X)
    iu=np.triu_indices(n,1); far=(iu[1]-iu[0])>excl_nodes; I,J=iu[0][far],iu[1][far]
    for _ in range(iters):
        X[0]=pin0
        X[-1]+= (head_target-X[-1])*0.5
        X[1:-1]+=bend*(X[:-2]+X[2:]-2*X[1:-1])
        d=X[J]-X[I]; dist=np.linalg.norm(d,axis=1); lim=2*R*1.03; hit=dist<lim
        if hit.any():
            push=d[hit]/np.maximum(dist[hit],1e-9)[:,None]*(lim-dist[hit])[:,None]*0.5
            np.add.at(X,I[hit],-push); np.add.at(X,J[hit],push)
        for _k in range(2):
            dd=np.diff(X,axis=0); ln=np.linalg.norm(dd,axis=1); cor=dd*((ln-seg)/np.maximum(ln,1e-9))[:,None]*0.5
            X[:-1]+=cor; X[1:]-=cor
        X[0]=pin0
    return X
def bake(tornado):
    X=resample_n(tornado,n); pin0=X[0].copy()
    head0=X[-1].copy(); axis_xz=np.array([X[:,0].mean(),0,X[:,2].mean()])
    top_y=X[:,1].min()
    lerp=lambda a,b,t:a+(b-a)*t
    over=np.array([axis_xz[0],top_y-30,axis_xz[2]])
    through=np.array([axis_xz[0],top_y+34,axis_xz[2]])
    hd=np.array([0.25,0,-1.0]);hd/=np.linalg.norm(hd)          # leave toward the viewer, a little to the left
    exitp=np.array([axis_xz[0],top_y+40,axis_xz[2]])-hd*75
    away=exitp+np.array([0,-62,0])-hd*18
    waypts=[head0,over,through,exitp,away]; durs=[40,45,50,70]
    keys=[X.copy()]; sepl=[]; radii=np.full(n,R)
    for w in range(4):
        for s in range(durs[w]):
            X=pbd_step(X,lerp(waypts[w],waypts[w+1],(s+1)/durs[w]),pin0); sepl.append(rod.min_sep(X,radii,4.5*R))
            if s%6==5: keys.append(X.copy())
    for s in range(60):
        X=pbd_step(X,away,pin0); sepl.append(rod.min_sep(X,radii,4.5*R))
        if s%12==11: keys.append(X.copy())
    return np.array(keys),min(sepl)
