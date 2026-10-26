use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Instant;

pub const BTN_LEFT: u32 = 0x110;
pub const BTN_RIGHT: u32 = 0x111;
pub const BTN_MIDDLE: u32 = 0x112;
const VERTICAL: u32 = 0;
const HORIZONTAL: u32 = 1;
const MANAGER: &str = "zwlr_virtual_pointer_manager_v1";

fn string(text: &str) -> Vec<u8> {
    let mut data = text.as_bytes().to_vec();
    data.push(0);
    let mut out = (data.len() as u32).to_le_bytes().to_vec();
    let pad = (4 - data.len() % 4) % 4;
    out.extend(data);
    out.extend(std::iter::repeat_n(0, pad));
    out
}

fn fixed(value: f64) -> i32 {
    (value * 256.0).round_ties_even() as i32
}

fn words(values: &[u32]) -> Vec<u8> {
    values.iter().flat_map(|v| v.to_le_bytes()).collect()
}

fn refused(what: &str) -> io::Error {
    io::Error::new(io::ErrorKind::ConnectionRefused, what.to_string())
}

pub struct VirtualPointer {
    sock: Option<UnixStream>,
    pointer: u32,
    next_id: u32,
    start: Instant,
}

impl VirtualPointer {
    pub fn new() -> VirtualPointer {
        VirtualPointer { sock: None, pointer: 0, next_id: 1, start: Instant::now() }
    }

    fn send(&mut self, obj: u32, opcode: u32, payload: &[u8]) -> io::Result<()> {
        let sock = self.sock.as_mut().ok_or_else(|| refused("not connected"))?;
        let mut msg = words(&[obj, ((8 + payload.len() as u32) << 16) | opcode]);
        msg.extend_from_slice(payload);
        sock.write_all(&msg)
    }

    fn new_id(&mut self) -> u32 {
        self.next_id += 1;
        self.next_id
    }

    fn connect(&mut self) -> io::Result<()> {
        let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
        let path = if display.starts_with('/') {
            display
        } else {
            format!("{}/{display}", std::env::var("XDG_RUNTIME_DIR").map_err(|_| refused("no XDG_RUNTIME_DIR"))?)
        };
        self.sock = Some(UnixStream::connect(path)?);
        self.next_id = 1;
        let (registry, done) = (self.new_id(), self.new_id());
        self.send(1, 1, &words(&[registry]))?;
        self.send(1, 0, &words(&[done]))?;
        let mut manager = None;
        let mut buf: Vec<u8> = Vec::new();
        let mut chunk = vec![0u8; 65536];
        'events: loop {
            let n = self.sock.as_mut().ok_or_else(|| refused("not connected"))?.read(&mut chunk)?;
            if n == 0 {
                return Err(refused("the compositor closed the connection"));
            }
            buf.extend_from_slice(&chunk[..n]);
            while buf.len() >= 8 {
                let word = |at: usize| u32::from_le_bytes(buf[at..at + 4].try_into().unwrap_or_default());
                let (obj, head) = (word(0), word(4));
                let size = (head >> 16) as usize;
                if size < 8 || buf.len() < size {
                    break;
                }
                let opcode = head & 0xffff;
                let body = buf[8..size].to_vec();
                buf.drain(..size);
                if obj == registry && opcode == 0 && body.len() >= 8 {
                    let get = |at: usize| u32::from_le_bytes(body[at..at + 4].try_into().unwrap_or_default());
                    let (name, length) = (get(0), get(4) as usize);
                    if length == 0 || body.len() < 8 + length {
                        continue;
                    }
                    let interface = String::from_utf8_lossy(&body[8..8 + length - 1]);
                    let at = 8 + length + (4 - length % 4) % 4;
                    if interface == MANAGER && body.len() >= at + 4 {
                        manager = Some((name, get(at)));
                    }
                } else if obj == 1 && opcode == 0 {
                    return Err(refused("the compositor refused a request"));
                } else if obj == done {
                    break 'events;
                }
            }
        }
        let (name, _version) = manager.ok_or_else(|| refused("the compositor has no virtual pointer"))?;
        let bound = self.new_id();
        let mut bind = words(&[name]);
        bind.extend(string(MANAGER));
        bind.extend(words(&[1, bound]));
        self.send(registry, 0, &bind)?;
        self.pointer = self.new_id();
        let pointer = self.pointer;
        self.send(bound, 0, &words(&[0, pointer]))?;
        if let Some(s) = &self.sock {
            s.set_nonblocking(true)?;
        }
        Ok(())
    }

    fn request(&mut self, opcode: u32, payload: &[u8], frame: bool) -> io::Result<()> {
        for attempt in 0..2 {
            let r = (|| {
                if self.sock.is_none() {
                    self.connect()?;
                }
                let pointer = self.pointer;
                self.send(pointer, opcode, payload)?;
                if frame {
                    self.send(pointer, 4, &[])?;
                }
                Ok(())
            })();
            match r {
                Ok(()) => return Ok(()),
                Err(e) => {
                    self.close();
                    if attempt == 1 {
                        return Err(e);
                    }
                }
            }
        }
        Ok(())
    }

    fn time(&self) -> u32 {
        self.start.elapsed().as_millis() as u32
    }

    pub fn move_by(&mut self, dx: f64, dy: f64) -> io::Result<()> {
        let p = words(&[self.time(), fixed(dx) as u32, fixed(dy) as u32]);
        self.request(0, &p, true)
    }

    pub fn press(&mut self, button: u32, down: bool) -> io::Result<()> {
        let p = words(&[self.time(), button, down as u32]);
        self.request(2, &p, true)
    }

    pub fn click(&mut self, button: u32, times: u32) -> io::Result<()> {
        for _ in 0..times {
            self.press(button, true)?;
            self.press(button, false)?;
        }
        Ok(())
    }

    pub fn scroll(&mut self, dx: f64, dy: f64) -> io::Result<()> {
        if dy != 0.0 {
            let p = words(&[self.time(), VERTICAL, fixed(dy) as u32]);
            self.request(3, &p, dx == 0.0)?;
        }
        if dx != 0.0 {
            let p = words(&[self.time(), HORIZONTAL, fixed(dx) as u32]);
            self.request(3, &p, true)?;
        }
        Ok(())
    }

    pub fn close(&mut self) {
        self.sock = None;
    }
}
