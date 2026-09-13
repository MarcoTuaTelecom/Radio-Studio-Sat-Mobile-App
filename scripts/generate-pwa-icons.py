#!/usr/bin/env python3
import os, struct, zlib, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else 'web/pwa'
os.makedirs(OUT, exist_ok=True)

BG = (17, 24, 39)
FG = (255, 255, 255)
ACCENT = (239, 59, 86)


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)


def rect(buf, size, x0, y0, x1, y1, color):
    x0=max(0,int(x0)); y0=max(0,int(y0)); x1=min(size,int(x1)); y1=min(size,int(y1))
    for y in range(y0,y1):
        row=y*size*3
        for x in range(x0,x1):
            i=row+x*3
            buf[i:i+3]=bytes(color)


def circle(buf,size,cx,cy,r,color):
    rr=r*r
    for y in range(max(0,cy-r),min(size,cy+r+1)):
        dy=(y-cy)*(y-cy)
        row=y*size*3
        for x in range(max(0,cx-r),min(size,cx+r+1)):
            if (x-cx)*(x-cx)+dy<=rr:
                i=row+x*3
                buf[i:i+3]=bytes(color)


def make(size, path):
    buf=bytearray(BG*(size*size))
    # white rounded-looking badge approximation
    circle(buf,size,size//2,size//2,int(size*.34),FG)
    rect(buf,size,size*.20,size*.36,size*.66,size*.64,BG)
    # STUDIO SAT visual mark: dark block + red level bars
    rect(buf,size,size*.25,size*.42,size*.55,size*.58,FG)
    bars=[.20,.34,.48,.68,.50]
    x=size*.62
    w=size*.035
    gap=size*.025
    for j,h in enumerate(bars):
        cx=x+j*(w+gap)
        rect(buf,size,cx,size*(.50-h/2),cx+w,size*(.50+h/2),ACCENT)
    raw=b''.join(b'\x00'+bytes(buf[y*size*3:(y+1)*size*3]) for y in range(size))
    data=(b'\x89PNG\r\n\x1a\n'+png_chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+png_chunk(b'IDAT',zlib.compress(raw,9))+png_chunk(b'IEND',b''))
    with open(path,'wb') as f:f.write(data)
    print(f'ICON={path} SIZE={size} BYTES={len(data)}')

for n in (192,512):
    make(n, os.path.join(OUT, f'icon-{n}.png'))
