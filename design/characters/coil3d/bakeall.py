"""Bakes every change of shape in Coil's graph and writes app/ChumsWatch/noodle-shapes.bin (Float32, little-endian):
  header: 'COIL', shapes S, points N, edges E
  S shapes × N points × 3
  per edge: from, to (int32), keys K (int32), seconds (float32), then K × N × 3
Shapes are named in shapes.NAMES order; the knot's shape is the last key of its tying."""
import numpy as np, struct, tube3d as T, rod
from shapes import R, L, NN, clear, rk, at
from morph import bake, stats, NS, project
import tie2
NAMES=['zigzag','tornado','spring','sleep','messy','shell','lolly','slinky','knot']
EDGES=[('zigzag','tornado'),('zigzag','spring'),('zigzag','sleep'),('zigzag','shell'),('zigzag','lolly'),('zigzag','slinky'),
       ('tornado','spring'),('tornado','sleep'),('tornado','messy'),('tornado','shell'),('tornado','lolly'),('spring','sleep'),
       ('shell','lolly'),('sleep','lolly')]
lib=dict(np.load('lib.npz'))
# the knot: tied from the tornado with a led head, baked with collisions (tie2), the head ending toward you
tie2.seg=L/(tie2.n-1)
keys,_=tie2.bake(lib['tornado'])
off=lib['tornado'].mean(0)-at(keys[0]).mean(0)
tieK=np.array([at(k,NS)+off for k in keys])
from scipy.ndimage import zoom
# densify the tie keys in time to match the other bakes, smooth, keep constraints
# densify the tie keys in time along smooth curves (Catmull-Rom), then make it smooth and valid like the others
def cr(P0,P1,P2,P3,w):
    w2=w*w;w3=w2*w
    return P0*(-0.5*w3+w2-0.5*w)+P1*(1.5*w3-2.5*w2+1)+P2*(-1.5*w3+2*w2+0.5*w)+P3*(0.5*w3-0.5*w2)
nk=len(tieK);dense=[]
for f in np.linspace(0,nk-1,170):
    i=min(nk-2,int(f));w=f-i
    dense.append(cr(tieK[max(0,i-1)],tieK[i],tieK[i+1],tieK[min(nk-1,i+2)],w))
from morph import finish
tieK=finish(np.array(dense),tieK[0],tieK[-1],glide=2)
lib['knot']=at(tieK[-1])
out=[]
for a,b in EDGES:
    best=None
    for mode in ('all','foot','head'):
        K=bake(lib[a],lib[b],mode)
        cl,mk,st,jk,err=stats(K,lib[b])
        score=st+0.5*jk+3*max(0,mk-1.2)+(50 if cl<1.0 else 0)
        if best is None or score<best[0]: best=(score,mode,K,(cl,mk,st,jk,err))
    _,mode,K,s=best
    print('%-8s -> %-8s %-4s clear %.2f R*k %.2f step %.1f jerk %.1f'%(a,b,mode,s[0],s[1],s[2],s[3]))
    out.append((a,b,K))
cl,mk,st,jk,err=stats(tieK,lib['knot'])
print('tornado  -> knot     tie  clear %.2f R*k %.2f step %.1f jerk %.1f'%(cl,mk,st,jk))
out.append(('tornado','knot',tieK))
def secs(K):
    travel=np.linalg.norm(np.diff(K,axis=0),axis=2).mean(axis=1).sum()
    return float(np.clip(1.3+travel/140,1.5,2.6))
buf=bytearray(b'COIL')+struct.pack('<3i',len(NAMES),NN,len(out))
for n in NAMES: buf+=np.asarray(lib[n],np.float32).tobytes()
for a,b,K in out:
    K64=np.array([at(k) for k in K[::2]])
    # the ends exactly the library's shapes, the difference eased out over the first and last few keys
    da=lib[a]-K64[0]; db=lib[b]-K64[-1]; m=6
    for i in range(min(m,len(K64))):
        w=1-i/m; K64[i]+=da*w; K64[-1-i]+=db*w
    K64=K64.astype(np.float32)
    buf+=struct.pack('<3if',NAMES.index(a),NAMES.index(b),len(K64),secs(K))+K64.tobytes()
open('../../../app/ChumsWatch/noodle-shapes.bin','wb').write(bytes(buf))
np.savez('baked.npz',**{'%s-%s'%(a,b):K for a,b,K in out})
print('bytes',len(buf))
