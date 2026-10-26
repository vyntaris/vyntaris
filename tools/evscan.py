#!/usr/bin/env python3
import os, re, struct, sys, time

name = sys.argv[1] if len(sys.argv) > 1 else "Ideapad extra buttons"
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 40
dev = None
for b in open("/proc/bus/input/devices").read().split("\n\n"):
    if f'N: Name="{name}"' in b:
        dev = "/dev/input/" + re.search(r"(event\d+)", b).group(1)
if not dev: sys.exit(f"no device named {name!r}")
fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
fmt = "llHHi"; size = struct.calcsize(fmt)
end = time.time() + secs; scan = None
print(f"reading {dev} for {secs:.0f}s", flush=True)
while time.time() < end:
    try: data = os.read(fd, size * 64)
    except BlockingIOError: time.sleep(0.02); continue
    for i in range(0, len(data), size):
        sec, usec, typ, code, val = struct.unpack(fmt, data[i:i + size])
        if typ == 4 and code == 4: scan = val
        elif typ == 1 and val == 1:
            print(f"{time.strftime('%H:%M:%S')}  scan=0x{scan or 0:x}  key={code}", flush=True)
