"""Which shape can turn straight into which, and how: each link's direction turns from one to the other, all at once
or as a front running from the foot or the head. Checked for keeping its parts apart and for not swinging round."""
import numpy as np, tube3d as T, rod
from shapes import R, L, clear, rk
def unit(v): return v/np.maximum(np.linalg.norm(v,axis=-1,keepdims=True),1e-12)
def weights(n,p,mode,wd=0.5):
    u=np.linspace(0,1,n)
    if mode=='all': x=np.full(n,p)
    elif mode=='foot': x=(p*(1+wd)-u)/wd
    else: x=(p*(1+wd)-(1-u))/wd
    x=np.clip(x,0,1); return x*x*(3-2*x)
def dirblend(A,B,w):
    ta=unit(np.diff(A,axis=0)); tb=unit(np.diff(B,axis=0)); n=len(ta)
    out=np.zeros_like(ta)
    for i in range(n):
        d=np.clip(ta[i]@tb[i],-1,1); th=np.arccos(d)
        if th<1e-6: out[i]=ta[i]; continue
        if th>3.1:
            ax=unit(np.cross(ta[i],np.array([0,0,1.0]))); out[i]=np.cos(w[i]*th)*ta[i]+np.sin(w[i]*th)*np.cross(ax,ta[i]); continue
        out[i]=(np.sin((1-w[i])*th)*ta[i]+np.sin(w[i]*th)*tb[i])/np.sin(th)
    seg=np.linalg.norm(np.diff(A,axis=0),axis=1).mean()
    P=np.vstack([[0,0,0],np.cumsum(out*seg,axis=0)])
    wm=w.mean()
    return P-P.mean(0)+(A.mean(0)*(1-wm)+B.mean(0)*wm)
def check(A,B,mode,steps=24):
    worst=9; maxk=0
    for p in np.linspace(0,1,steps):
        e=p*p*(3-2*p); w=weights(len(A)-1,e,mode)
        P=dirblend(A,B,w); worst=min(worst,clear(P)); maxk=max(maxk,rk(P))
    return worst,maxk
if __name__=='__main__':
    lib=dict(np.load('lib.npz'))
    names=list(lib)
    table={}
    for a in names:
        for b in names:
            if a>=b: continue
            res={m:check(lib[a],lib[b],m) for m in ('all','foot','head')}
            best=max(res,key=lambda m:res[m][0])
            table[(a,b)]=(best,)+res[best]
            print('%-8s <-> %-8s best %-4s clear %.2f  R*k %.2f   (all %.2f foot %.2f head %.2f)'%(a,b,best,res[best][0],res[best][1],res['all'][0],res['foot'][0],res['head'][0]))
    import pickle; pickle.dump(table,open('trans.pkl','wb'))
