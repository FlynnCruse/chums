"""Coil's shape library: every shape the same tube (length L, radius R), its bends round (no tighter than ~1.25 R), its
parts never closer than the tube's width, standing on the ground (y = G, y down, z toward you), fitting the screen."""
import numpy as np, tube3d as T, rod
from scipy.ndimage import gaussian_filter1d
from zigzag3d import make as make_zigzag
R=T.R; NN=64; G=70.0
ZIG,_=make_zigzag(kmax=0.6); L=T.length(ZIG)
SEG=L/(NN-1)
def at(P,n=NN): Q,_=T.resample(P,n); return Q
def turns(P):
    d=np.diff(P,axis=0);d/=np.linalg.norm(d,axis=1,keepdims=True)
    return np.arccos(np.clip((d[:-1]*d[1:]).sum(1),-1,1))
def rk(P): return turns(P).max()/SEG*R
def clear(P): return rod.min_sep(P,np.full(len(P),R),4.5*R)
def ground(P):
    P=P.copy();P[:,1]+=G-P[:,1].max();c=P.mean(0);P[:,0]-=c[0];P[:,2]-=c[2];return P
def solve_len(make,lo,hi):
    for _ in range(60):
        m=(lo+hi)/2
        if T.length(make(m))<L: lo=m
        else: hi=m
    return make(hi)
def rotx(P,a): c,s=np.cos(a),np.sin(a); return P@np.array([[1,0,0],[0,c,-s],[0,s,c]]).T
def roty(P,a): c,s=np.cos(a),np.sin(a); return P@np.array([[c,0,s],[0,1,0],[-s,0,c]]).T
def rotz(P,a): c,s=np.cos(a),np.sin(a); return P@np.array([[c,-s,0],[s,c,0],[0,0,1]]).T
def helix(r0,r1,pitch,turns_,tilt=0.0,phase=0.0):
    t=np.linspace(0,turns_*2*np.pi,2000);k=t/t[-1];r=r0+(r1-r0)*k
    P=np.stack([r*np.cos(t+phase),-(k*turns_*pitch),r*np.sin(t+phase)],1)
    return rotx(P,tilt) if tilt else P
def shell(stem=0.0, rin=19.0, b=3.6, c=3.5, phase=np.pi/2, hand=1):
    """A spiral facing you, wound in to the head at its middle (inner turns come forward); optionally on a stem from
    the ground (the tail runs straight down from the outer turn)."""
    def mk(Th):
        th=np.linspace(0,Th,3000)
        r=rin+b*(Th-th); a=phase+hand*th
        P=np.stack([r*np.cos(a),r*np.sin(a),c*th],1)
        if stem>0:
            t0=P[1]-P[0];t0/=np.linalg.norm(t0)
            S=np.array([P[0]-t0*s for s in np.linspace(stem,0,200,endpoint=False)])
            P=np.vstack([S,P])
        return P
    return solve_len(mk,1.0,30.0)
def slinky(r=24.0,pitch=36.0,tilt=0.25,yaw=0.35):
    """A spring lying on its side, its axis across the screen."""
    def mk(tr):
        t=np.linspace(0,tr*2*np.pi,2000)
        P=np.stack([-(t/(2*np.pi))*pitch, r*np.cos(t+np.pi/2), r*np.sin(t+np.pi/2)],1)
        return roty(rotx(P,tilt),yaw)
    return solve_len(mk,1.0,6.0)
def smooth_to(P,kmax=0.85):
    D=at(P,400);best=None
    for sig in np.arange(0.0,12.1,0.5):
        if sig>0:
            k=int(4*sig)+2;t0=D[1]-D[0];t1=D[-1]-D[-2]
            pad=np.vstack([D[0]-t0*np.arange(k,0,-1)[:,None],D,D[-1]+t1*np.arange(1,k+1)[:,None]])
            Q=gaussian_filter1d(pad,sig,axis=0)[k:-k]
        else: Q=D.copy()
        c=Q.mean(0);Q=(Q-c)*(L/T.length(Q))+c;Q=at(Q)
        m=rk(Q)
        if best is None or m<best[0]: best=(m,Q)
        if m<=kmax: break
    return best[1]
def library():
    S={}
    S['zigzag']=ZIG
    S['tornado']=solve_len(lambda tr:helix(20,46,38,tr),1,6)
    S['spring']=solve_len(lambda tr:helix(26,26,58,tr),1,6)
    S['sleep']=solve_len(lambda tr:helix(52,20,2*R*1.02,tr,tilt=-0.42,phase=2.2),1,6)
    S['messy']=np.load('messy.npy')
    S['shell']=shell(hand=1)
    S['lolly']=shell(stem=62.0,rin=19.0,b=3.6,c=3.5,phase=np.pi,hand=1)
    S['slinky']=slinky()
    out={}
    for k,P in S.items(): out[k]=ground(smooth_to(P*(L/T.length(P))))
    return out
if __name__=='__main__':
    lib=library()
    for k,P in lib.items(): print('%-8s len %.0f  clearance %.2f  R*k %.2f  extent %s'%(k,T.length(P),clear(P),rk(P),np.ptp(P,axis=0).round(0)))
    np.savez('lib.npz',**lib)
