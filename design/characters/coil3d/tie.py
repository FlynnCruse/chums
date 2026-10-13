"""Offline bake of the knot entry: a PBD rope (fixed length, 2R self-collision, bending smoothness, foot pinned) whose
head is led on a path: top of the tornado coil -> down through the top ring -> out between the rings -> away, which
tightens an overhand knot. Keyframes are recorded as rods; the runtime would blend keyframe to keyframe."""
import numpy as np, tube3d as T, rod
R=T.R; n=100; seg=T.L/(n-1)
def resample_n(P,m): Q,_=T.resample(P,m); return Q
def pbd_step(X, head_target, pin0, iters=12, excl_nodes=11, bend=0.08):
    n=len(X)
    iu=np.triu_indices(n,1); far=(iu[1]-iu[0])>excl_nodes; I,J=iu[0][far],iu[1][far]
    for _ in range(iters):
        X[0]=pin0
        X[-1]+= (head_target-X[-1])*0.5
        # bending: pull each node toward the midpoint of its neighbours a little (smoothness)
        X[1:-1]+=bend*(X[:-2]+X[2:]-2*X[1:-1])
        # collisions
        d=X[J]-X[I]; dist=np.linalg.norm(d,axis=1); lim=2*R*1.03; hit=dist<lim
        if hit.any():
            push=d[hit]/np.maximum(dist[hit],1e-9)[:,None]*(lim-dist[hit])[:,None]*0.5
            np.add.at(X,I[hit],-push); np.add.at(X,J[hit],push)
        # lengths
        for _k in range(2):
            dd=np.diff(X,axis=0); ln=np.linalg.norm(dd,axis=1); cor=dd*((ln-seg)/np.maximum(ln,1e-9))[:,None]*0.5
            X[:-1]+=cor; X[1:]-=cor
        X[0]=pin0
    return X
# start: the tornado (head on top ring, radius 44)
P=resample_n(T.tornado(0.0),n); X=P.copy(); pin0=X[0].copy()
head0=X[-1].copy(); axis_xz=np.array([X[:,0].mean(),0,X[:,2].mean()])
top_y=X[:,1].min()
# path for the head (world pts): over the axis, down through the ring, out sideways, then away
def lerp(a,b,t): return a+(b-a)*t
over=np.array([axis_xz[0],top_y-30,axis_xz[2]])
through=np.array([axis_xz[0],top_y+34,axis_xz[2]])
# exit direction: opposite to where the head started (so it crosses the standing part)
hd=head0-axis_xz; hd[1]=0; hd/=np.linalg.norm(hd)
exitp=np.array([axis_xz[0],top_y+40,axis_xz[2]])-hd*75
away=exitp+np.array([0,-70,0])-hd*25
waypts=[head0,over,through,exitp,away]; durs=[40,45,50,70]
keys=[X.copy()]; sepl=[]
radii=np.full(n,R)
for w in range(4):
    for s in range(durs[w]):
        tgt=lerp(waypts[w],waypts[w+1],(s+1)/durs[w])
        X=pbd_step(X,tgt,pin0)
        sepl.append(rod.min_sep(X,radii,4.5*R))
    keys.append(X.copy())
# then settle: let the knot find its shape with the head held
for s in range(60): X=pbd_step(X,away,pin0); sepl.append(rod.min_sep(X,radii,4.5*R))
keys.append(X.copy())
print('sim min clearance over the whole path: %.2f (worst frame %d of %d)'%(min(sepl),int(np.argmin(sepl)),len(sepl)))
print('final length %.1f, extent %s, head y %.0f'%(T.length(X),np.ptp(X,axis=0).round(0),X[-1,1]))
np.save('tie_keys.npy',np.array(keys))
# playback test: blend consecutive keyframes in rod space (10 steps each) and measure clearance
rods=[rod.to_rod(k) for k in keys]
worst=9
for a in range(len(rods)-1):
    for t in np.linspace(0,1,11):
        Q=rod.from_rod(rod.blend_rods(rods[a],rods[a+1],t)); worst=min(worst,rod.min_sep(Q,radii,4.5*R))
print('kinematic playback between the %d keyframes: min clearance %.2f'%(len(keys),worst))
# how many keyframes would be needed: record every 15 sim steps instead
