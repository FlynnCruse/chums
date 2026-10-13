import numpy as np, re
src=open('CoilRest-fit.swift').read()
def arr3(name):
    body=src.split('static let %s:'%name)[1].split('\n')[0]
    return np.array([[float(a),float(b),float(c)] for a,b,c in re.findall(r'SIMD3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\)',body)])
def arrf(name):
    body=src.split('static let %s:'%name)[1].split('\n')[0]
    return np.array([float(v) for v in re.findall(r'-?\d+\.\d+',body.split('=')[1])])
nodes=np.array([[float(a),float(b)] for a,b in re.findall(r'SIMD2\(([-\d.]+), ([-\d.]+)\)',src.split('static let nodes')[1].split('\n')[0])])
ALB=arr3('albedo');LIGHT=arrf('light');SHEEN=arrf('sheen')
R=14.5
def resample(P,n):
    s=np.concatenate([[0],np.cumsum(np.linalg.norm(np.diff(P,axis=0),axis=1))]);t=np.linspace(0,s[-1],n)
    return np.stack([np.interp(t,s,P[:,k]) for k in range(P.shape[1])],1),s[-1]
def length(P): return np.linalg.norm(np.diff(P,axis=0),axis=1).sum()
# --- poses (pt; y down; z toward you; centred near the origin, the ground at y=+GROUND) ---
GROUND=78.0
def zigzag():
    P=np.c_[nodes,np.zeros(len(nodes))]
    d=P[-1]-P[-3];d/=np.linalg.norm(d)
    ext=np.array([P[-1]+d*k for k in np.linspace(2,30,15)])
    P=np.vstack([P,ext])
    P,_=resample(P,400);u=np.linspace(0,1,len(P))
    P[:,2]=(u-0.5)*115
    return P
L=length(zigzag())
def fitlen(P,c=None):
    l=length(P);c=P.mean(0) if c is None else c
    return (P-c)*(L/l)+c
def helix(r0,r1,pitch,turns,phase=0.0,tilt=0.0,up=True):
    t=np.linspace(0,turns*2*np.pi,800);k=t/t[-1]
    r=r0+(r1-r0)*k
    P=np.stack([r*np.cos(t+phase),-(k*turns*pitch),r*np.sin(t+phase)],1)
    if tilt:
        c,s=np.cos(tilt),np.sin(tilt);P=P@np.array([[1,0,0],[0,c,-s],[0,s,c]]).T
    return P
def tornado(phase=0.0):
    # narrow at the foot, widening as it rises; the head at the top
    for turns in np.linspace(1.5,3.5,81):
        P=helix(14,44,38,turns,phase)
        if length(P)>=L: break
    P,_=resample(P,400);P[:,1]+=GROUND-P[:,1].max();P[:,0]-=P[:,0].mean()*0;return P
def sleepcoil(phase=0.0):
    # wide at the bottom, tighter going up, stacked (touching), seen a little from above
    for turns in np.linspace(1.2,3.5,93):
        P=helix(52,20,2*R*1.02,turns,phase+2.2,tilt=-0.42)
        if length(P)>=L: break
    P,_=resample(P,400);P[:,1]+=GROUND-P[:,1].max();return P
def spring(phase=0.0):
    for turns in np.linspace(1.2,4,113):
        P=helix(26,26,58,turns,phase)
        if length(P)>=L: break
    P,_=resample(P,400);P[:,1]+=GROUND-P[:,1].max();return P
def knot(phase=0.0,zk=2.8):
    t=np.linspace(0.75,2*np.pi-0.75,900)
    P=np.stack([np.sin(t)+2*np.sin(2*t),np.cos(t)-2*np.cos(2*t),-zk*np.sin(3*t)],1)
    c,s=np.cos(phase),np.sin(phase);P=P@np.array([[c,0,s],[0,1,0],[-s,0,c]]).T
    P=P*(L/length(P));P,_=resample(P,400);P[:,1]+=GROUND-P[:,1].max()-6;return P
def clump(phase=0.0):
    t=np.linspace(0,1,900);a=2*np.pi*1.75*t;b=np.pi*(0.9*t-0.45)+0.3*np.sin(a*1.3)
    rho=40+12*np.sin(a*2.0)
    P=np.stack([rho*np.cos(a+phase)*np.cos(b),rho*np.sin(b),rho*np.sin(a+phase)*np.cos(b)],1)
    P=P*(L/length(P));P,_=resample(P,400);P[:,1]+=GROUND-P[:,1].max();return P
def mindist(P,R=R):
    n=len(P);s=np.concatenate([[0],np.cumsum(np.linalg.norm(np.diff(P,axis=0),axis=1))])
    D=np.linalg.norm(P[:,None]-P[None],axis=2);far=np.abs(s[:,None]-s[None])>3.2*R
    return (D[far]).min()/(2*R)
