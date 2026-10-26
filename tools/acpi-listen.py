#!/usr/bin/env python3
import socket, struct, time

NETLINK_GENERIC = 16
GENL_ID_CTRL = 0x10
CTRL_CMD_GETFAMILY = 3
CTRL_ATTR_FAMILY_ID, CTRL_ATTR_FAMILY_NAME, CTRL_ATTR_MCAST_GROUPS = 1, 2, 7
CTRL_ATTR_MCAST_GRP_NAME, CTRL_ATTR_MCAST_GRP_ID = 1, 2

def attrs(buf):
    out = {}
    while len(buf) >= 4:
        ln, typ = struct.unpack("HH", buf[:4])
        if ln < 4: break
        out[typ & 0x3fff] = buf[4:ln]
        buf = buf[(ln + 3) & ~3:]
    return out

s = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, NETLINK_GENERIC)
s.bind((0, 0))
name = b"acpi_event\0"
attr = struct.pack("HH", 4 + len(name), CTRL_ATTR_FAMILY_NAME) + name
attr += b"\0" * ((4 - len(attr) % 4) % 4)
genl = struct.pack("BBH", CTRL_CMD_GETFAMILY, 1, 0)
msg = struct.pack("IHHII", 16 + len(genl) + len(attr), GENL_ID_CTRL, 1, 1, 0) + genl + attr
s.send(msg)
reply = s.recv(65536)
a = attrs(reply[20:])
group = None
for g in attrs(a[CTRL_ATTR_MCAST_GROUPS]).values():
    ga = attrs(g)
    group = struct.unpack("I", ga[CTRL_ATTR_MCAST_GRP_ID])[0]
s.setsockopt(270, 1, group)
print("listening for ACPI events…", flush=True)
while True:
    data = s.recv(65536)
    ev = attrs(data[20:]).get(1)
    if not ev: continue
    cls, bus = ev[:20].split(b"\0")[0].decode(), ev[20:35].split(b"\0")[0].decode()
    typ, dat = struct.unpack("II", ev[36:44])
    print(f"{time.strftime('%H:%M:%S')}  {cls} {bus} {typ:08x} {dat:08x}", flush=True)
