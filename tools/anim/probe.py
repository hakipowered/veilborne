"""Summarise a probe dump: hand speeds per normalized time. probe.py < dump"""
import sys, math
rows=[]
for l in sys.stdin:
    if l.startswith("P "):
        v=list(map(float,l.split()[1:])); rows.append(v)
names=["RH","LH","Hips","RF","LF","Head"]
prev=None
for r in rows:
    if prev:
        sp=[]
        for k in range(6):
            a=r[1+3*k:4+3*k]; b=prev[1+3*k:4+3*k]
            sp.append(math.dist(a,b)*30)
        print("%.3f  RH %4.1f LH %4.1f hips %4.1f  hipsY %.2f headY %.2f RHy %.2f" % (r[0], sp[0], sp[1], sp[2], r[1+3*2+1], r[1+3*5+1], r[2]))
    prev=r
