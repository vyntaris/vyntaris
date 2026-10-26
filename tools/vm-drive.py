#!/usr/bin/env python3
import json, os, socket, sys, time

KEYS = {' ': 'spc', '/': 'slash', '-': 'minus', '.': 'dot', '|': 'shift-backslash', '>': 'shift-dot',
        '<': 'shift-comma', '_': 'shift-minus', ':': 'shift-semicolon', '=': 'equal', '*': 'shift-8',
        '~': 'shift-grave', "'": 'apostrophe', '"': 'shift-apostrophe', '$': 'shift-4', '&': 'shift-7',
        ';': 'semicolon', ',': 'comma', '(': 'shift-9', ')': 'shift-0', '\n': 'ret', '!': 'shift-1',
        '@': 'shift-2', '#': 'shift-3', '%': 'shift-5', '^': 'shift-6', '+': 'shift-equal',
        '[': 'bracket_left', ']': 'bracket_right', '{': 'shift-bracket_left', '}': 'shift-bracket_right',
        '\\': 'backslash', '?': 'shift-slash', '\t': 'tab'}
W, H = int(os.environ.get('VM_W', 1280)), int(os.environ.get('VM_H', 800))

def monitor(cmd):
    s = socket.socket(socket.AF_UNIX)
    s.connect('monitor.sock')
    s.sendall((cmd + '\n').encode())
    time.sleep(0.07)
    s.close()

def qmp(events_list):
    s = socket.socket(socket.AF_UNIX)
    s.connect('qmp.sock')
    f = s.makefile()
    f.readline()
    s.sendall(b'{"execute":"qmp_capabilities"}\n')
    f.readline()
    for events in events_list:
        if events == 'sleep':
            time.sleep(0.12)
            continue
        s.sendall((json.dumps({'execute': 'input-send-event', 'arguments': {'events': events}}) + '\n').encode())
        f.readline()
    s.close()

def at(x, y):
    return [{'type': 'abs', 'data': {'axis': 'x', 'value': int(x) * 32767 // W}},
            {'type': 'abs', 'data': {'axis': 'y', 'value': int(y) * 32767 // H}}]

def btn(name, down):
    return [{'type': 'btn', 'data': {'down': down, 'button': name}}]

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == 'type':
    for ch in args[0].encode().decode('unicode_escape'):
        monitor('sendkey ' + (KEYS.get(ch) or ('shift-' + ch.lower() if ch.isupper() else ch)))
elif cmd == 'key':
    monitor('sendkey ' + args[0])
elif cmd == 'click':
    qmp([at(*args[:2]), 'sleep', btn('left', True), 'sleep', btn('left', False)])
elif cmd == 'scroll':
    n = int(args[2])
    b = 'wheel-down' if n > 0 else 'wheel-up'
    qmp([at(*args[:2])] + [e for _ in range(abs(n)) for e in (btn(b, True), btn(b, False))])
elif cmd == 'shot':
    monitor('screendump %s -f png' % os.path.abspath(args[0]))
    time.sleep(1)
else:
    sys.exit(__doc__)
