"""The rest pose: the reference's zigzag as seen from the front (x, y traced), given the depth (z) that lets a round tube
of this width make its bends: each elbow turns partly through depth, so no bend is tighter than ~1.3 tube radii, while
later folds stay in front of earlier ones."""
import numpy as np, tube3d as T
from scipy.optimize import minimize
R=T.R
def make(n=96, kmax=0.72, ramp=80.0):
    zig=T.zigzag()
    D,_=T.resample(zig[:,:2],n)                      # the front view, evenly along it
    u=np.linspace(0,1,n); z0=(u-0.5)*ramp
    def curve(z): return np.c_[D,z]
    def obj(z):
        P=curve(z); d=np.diff(P,axis=0); sl=np.linalg.norm(d,axis=1); t=d/sl[:,None]
        c=np.clip((t[:-1]*t[1:]).sum(1),-1,1); th=np.arccos(c); k=th/((sl[:-1]+sl[1:])/2)*R
        over=np.maximum(0,k-kmax)
        dz2=np.diff(z,2)
        return 400*np.sum(over**2)+0.02*np.sum(dz2**2)+0.0005*np.sum((z-z0)**2)
    res=minimize(obj,z0,method='L-BFGS-B',options=dict(maxiter=4000))
    P=curve(res.x)
    return P,res
if __name__=='__main__':
    P,res=make()
    d=np.diff(P,axis=0);sl=np.linalg.norm(d,axis=1);t=d/sl[:,None];th=np.arccos(np.clip((t[:-1]*t[1:]).sum(1),-1,1))
    print('max R*k %.2f, length %.0f, z range %.0f..%.0f'%((th/((sl[:-1]+sl[1:])/2)*R).max(),T.length(P),P[:,2].min(),P[:,2].max()))
    np.save('zigzag3d.npy',P)
