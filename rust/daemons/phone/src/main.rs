mod desktop;
mod device;
mod protocol;
mod wayland;

use desktop::Desktop;
use device::Device;
use protocol::{CONFIG, Link, MAX_UNPAIRED, Me, PROTOCOL, decode, encode, read_line, valid_id};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::future::Future;
use std::net::{IpAddr, SocketAddr};
use std::path::PathBuf;
use std::rc::Rc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream, UdpSocket, UnixListener, UnixStream};
use tokio::sync::mpsc;
use tokio::time::timeout;

pub struct State {
    pub devices: HashMap<String, Device>,
    clients: Vec<mpsc::UnboundedSender<Vec<u8>>>,
    pending: bool,
    pub clipboard_time: i64,
    tcp_port: u16,
    udp: Option<Rc<UdpSocket>>,
    answered: HashMap<String, Instant>,
}

pub struct Ctx {
    pub me: RefCell<Me>,
    pub desktop: Desktop,
    pub st: RefCell<State>,
    links: Cell<u64>,
}

pub fn spawn(ctx: &Rc<Ctx>, work: impl Future<Output = Result<(), String>> + 'static) {
    let ctx = ctx.clone();
    tokio::task::spawn_local(async move {
        if let Err(e) = work.await {
            report(&ctx, &e);
        }
    });
}

fn state(ctx: &Ctx) -> Value {
    let st = ctx.st.borrow();
    let mut devices: Vec<&Device> = st.devices.values().collect();
    devices.sort_by_key(|d| (!d.paired(), d.link.is_none(), d.name.to_lowercase()));
    json!({"running": true, "name": ctx.me.borrow().name, "devices": devices.iter().map(|d| d.state()).collect::<Vec<_>>()})
}

pub fn changed(ctx: &Rc<Ctx>) {
    if std::mem::replace(&mut ctx.st.borrow_mut().pending, true) {
        return;
    }
    let ctx = ctx.clone();
    tokio::task::spawn_local(async move {
        tokio::time::sleep(Duration::from_millis(100)).await;
        ctx.st.borrow_mut().pending = false;
        let msg = json!({"state": state(&ctx)});
        send_clients(&ctx, &msg);
    });
}

pub fn report(ctx: &Ctx, text: &str) {
    send_clients(ctx, &json!({"error": text}));
}

fn send_clients(ctx: &Ctx, msg: &Value) {
    let data = encode(msg);
    ctx.st.borrow_mut().clients.retain(|c| c.send(data.clone()).is_ok());
}

pub fn clipboard_changed(ctx: &Rc<Ctx>, text: &str) {
    ctx.st.borrow_mut().clipboard_time = protocol::now_ms();
    let ids: Vec<String> = ctx.st.borrow().devices.keys().cloned().collect();
    for id in ids {
        device::clipboard_changed(ctx, &id, text);
    }
}

async fn client(ctx: Rc<Ctx>, stream: UnixStream) {
    let (read, mut write) = stream.into_split();
    let (tx, mut rx) = mpsc::unbounded_channel::<Vec<u8>>();
    let _ = tx.send(encode(&json!({"state": state(&ctx)})));
    ctx.st.borrow_mut().clients.push(tx.clone());
    tokio::task::spawn_local(async move {
        while let Some(data) = rx.recv().await {
            if write.write_all(&data).await.is_err() {
                break;
            }
        }
    });
    let mut read = BufReader::new(read);
    while let Some(line) = read_line(&mut read).await {
        let result = match serde_json::from_slice::<Value>(&line) {
            Ok(Value::Object(cmd)) => command(&ctx, &cmd).await,
            Ok(_) => Err("not a command".into()),
            Err(e) => Err(e.to_string()),
        };
        if let Err(e) = result {
            let _ = tx.send(encode(&json!({"error": if e.is_empty() { "That didn't work".into() } else { e }})));
        }
    }
    ctx.st.borrow_mut().clients.retain(|c| !c.same_channel(&tx));
}

async fn command(ctx: &Rc<Ctx>, cmd: &serde_json::Map<String, Value>) -> Result<(), String> {
    let mut what = cmd.get("do").and_then(Value::as_str).unwrap_or("").to_string();
    let mut id = cmd.get("id").map(protocol::text).unwrap_or_default();
    match what.as_str() {
        "rename" => {
            let name = device::clean(&cmd.get("name").map(protocol::text).unwrap_or_default());
            if name.is_empty() {
                return Err("a name of 1 to 32 letters".into());
            }
            ctx.me.borrow_mut().name = name;
            ctx.me.borrow().save();
            let identity = ctx.me.borrow().identity(None, None);
            for d in ctx.st.borrow().devices.values() {
                if let Some(l) = &d.link {
                    l.post(&identity);
                }
            }
            changed(ctx);
            return Ok(());
        }
        "refresh" => {
            announce(ctx, None);
            return Ok(());
        }
        "send" => {
            id = ctx.st.borrow().devices.values().find(|d| d.paired() && d.link.is_some()).map(|d| d.id.clone())
                .ok_or("No phone connected")?;
            what = "share".into();
        }
        _ => {}
    }
    if !ctx.st.borrow().devices.contains_key(&id) {
        return Err("no such phone".into());
    }
    match what.as_str() {
        "pair" => device::request_pairing(ctx, &id)?,
        "accept" => device::accept_pairing(ctx, &id)?,
        "reject" => device::cancel_pairing(ctx, &id)?,
        "unpair" => device::unpair(ctx, &id)?,
        "ring" => device::ring(ctx, &id)?,
        "ping" => device::ping(ctx, &id)?,
        "clipboard" => device::send_clipboard(ctx, &id)?,
        "share" => {
            let paths: Vec<PathBuf> = cmd.get("paths").and_then(Value::as_array).into_iter().flatten()
                .map(|p| std::path::absolute(protocol::text(p)).unwrap_or_default()).collect();
            if let Some(bad) = paths.iter().find(|p| !p.is_file()) {
                return Err(format!("not a file: {}", bad.display()));
            }
            if paths.is_empty() {
                return Err("not a file: none given".into());
            }
            let c = ctx.clone();
            spawn(ctx, async move { device::share(&c, &id, &paths).await });
        }
        "pick" => {
            let c = ctx.clone();
            spawn(ctx, async move { device::pick(&c, &id).await });
        }
        "feature" => {
            let plugin = cmd.get("plugin").map(protocol::text).unwrap_or_default();
            device::set_feature(ctx, &id, &plugin, cmd.get("on").is_some_and(protocol::truthy))?;
        }
        other => return Err(format!("no such command: {other}")),
    }
    changed(ctx);
    Ok(())
}

async fn broadcast_addresses(ctx: &Ctx) -> Vec<IpAddr> {
    if CONFIG.testing {
        return vec![[127, 0, 0, 1].into()];
    }
    let out: Value = serde_json::from_str(&ctx.desktop.output(&["ip", "-j", "-4", "addr", "show", "up"]).await).unwrap_or_default();
    let mut found: Vec<IpAddr> = out.as_array().into_iter().flatten().filter(|i| i["ifname"] != "lo")
        .flat_map(|i| i["addr_info"].as_array().cloned().unwrap_or_default())
        .filter_map(|a| a["broadcast"].as_str().and_then(|b| b.parse().ok())).collect();
    found.sort();
    found.dedup();
    found.push([255, 255, 255, 255].into());
    found
}

fn announce(ctx: &Rc<Ctx>, to: Option<Vec<IpAddr>>) {
    let ctx = ctx.clone();
    tokio::task::spawn_local(async move {
        let Some(udp) = ctx.st.borrow().udp.clone() else { return };
        let data = encode(&ctx.me.borrow().identity(Some(ctx.st.borrow().tcp_port), None));
        let to = match to {
            Some(t) => t,
            None => broadcast_addresses(&ctx).await,
        };
        for address in to {
            let _ = udp.send_to(&data, SocketAddr::new(address, CONFIG.peer_udp_port)).await;
        }
    });
}

async fn discovery(ctx: Rc<Ctx>, udp: Rc<UdpSocket>) {
    let mut buf = vec![0u8; 65536];
    loop {
        let Ok((n, from)) = udp.recv_from(&mut buf).await else { continue };
        let Some(pkt) = decode(&buf[..n]) else { continue };
        if pkt["type"] != "kdeconnect.identity" {
            continue;
        }
        let id = protocol::text(&pkt["body"]["deviceId"]);
        if !valid_id(&id) || id == ctx.me.borrow().id || (from.ip().is_loopback() && !CONFIG.testing) {
            continue;
        }
        let mut st = ctx.st.borrow_mut();
        if st.devices.get(&id).is_some_and(|d| d.link.is_some()) {
            continue;
        }
        let now = Instant::now();
        if st.answered.get(&id).is_some_and(|t| now.duration_since(*t) < Duration::from_secs(1)) {
            continue;
        }
        st.answered.insert(id, now);
        drop(st);
        announce(&ctx, Some(vec![from.ip()]));
    }
}

async fn connected(ctx: Rc<Ctx>, tcp: TcpStream, address: SocketAddr) {
    let keepalive = socket2::TcpKeepalive::new().with_time(Duration::from_secs(30)).with_interval(Duration::from_secs(10)).with_retries(3);
    let _ = socket2::SockRef::from(&tcp).set_tcp_keepalive(&keepalive);
    if let Err(e) = handshake(&ctx, tcp, address.ip()).await {
        eprintln!("phone link: {}: {e}", address.ip());
    }
}

fn version_of(body: &Value) -> Result<i64, String> {
    let v = &body["protocolVersion"];
    if !protocol::truthy(v) {
        return Ok(0);
    }
    protocol::as_int(v).ok_or_else(|| "not a phone".into())
}

async fn handshake(ctx: &Rc<Ctx>, tcp: TcpStream, address: IpAddr) -> Result<(), String> {
    let mut raw = BufReader::new(tcp);
    let hello = timeout(Duration::from_secs(5), read_line(&mut raw)).await.map_err(|_| "it said nothing")?.and_then(|l| decode(&l));
    let hello = hello.filter(|h| h["type"] == "kdeconnect.identity").ok_or("not a phone")?;
    if !raw.buffer().is_empty() {
        return Err("not a phone: it went on before TLS".into());
    }
    let body = &hello["body"];
    let (id, version) = (protocol::text(&body["deviceId"]), version_of(body)?);
    let me_id = ctx.me.borrow().id.clone();
    let target = body.get("targetDeviceId").filter(|t| protocol::truthy(t)).map(protocol::text);
    if !valid_id(&id) || id == me_id || version < PROTOCOL || target.is_some_and(|t| t != me_id) {
        return Err("not a phone for us".into());
    }
    let known_paired = ctx.st.borrow().devices.get(&id).filter(|d| d.paired()).map(|d| d.cert.clone());
    if known_paired.is_none() && ctx.st.borrow().devices.values().filter(|d| !d.paired()).count() >= MAX_UNPAIRED {
        return Err("too many unpaired phones".into());
    }
    let tls = ctx.me.borrow().client_context()?;
    let stream = protocol::tls_client(&tls, raw.into_inner()).await?;
    let cert = protocol::peer_cert(&stream).ok_or("no certificate")?;
    if let Some(known) = &known_paired
        && known.as_deref() != Some(&cert[..])
    {
        return Err("a phone with another's id: not let in".into());
    }
    let (read, mut write) = tokio::io::split(stream);
    let mut read = BufReader::new(read);
    let mine = encode(&ctx.me.borrow().identity(None, None));
    write.write_all(&mine).await.map_err(|e| e.to_string())?;
    let identity = timeout(Duration::from_secs(5), read_line(&mut read)).await.map_err(|_| "it said nothing inside")?.and_then(|l| decode(&l));
    let identity = identity.filter(|i| i["type"] == "kdeconnect.identity" && protocol::text(&i["body"]["deviceId"]) == id
        && version_of(&i["body"]).ok() == Some(version)).ok_or("the phone changed who it is halfway")?;
    if protocol::common_name(&cert) != id {
        return Err("the certificate isn't the phone's".into());
    }

    let (tx, mut rx) = mpsc::unbounded_channel::<Vec<u8>>();
    tokio::task::spawn_local(async move {
        while let Some(data) = rx.recv().await {
            if write.write_all(&data).await.is_err() {
                break;
            }
        }
        let _ = write.shutdown().await;
    });
    let serial = ctx.links.get() + 1;
    ctx.links.set(serial);
    let link = Rc::new(Link::new(serial, tx, address, cert));
    ctx.st.borrow_mut().devices.entry(id.clone()).or_insert_with(|| Device::new(&id));
    let body = identity["body"].as_object().cloned().unwrap_or_default();
    device::attach(ctx, &id, link.clone(), &body);
    changed(ctx);
    loop {
        let line = tokio::select! {
            line = read_line(&mut read) => line,
            _ = link.closed.notified() => None,
        };
        let Some(line) = line else { break };
        let ours = ctx.st.borrow().devices.get(&id).and_then(|d| d.link.as_ref().map(|l| l.serial)) == Some(serial);
        if !ours {
            break;
        }
        if let Some(pkt) = decode(&line) {
            device::handle(ctx, &id, pkt).await;
        }
    }
    device::detach(ctx, &id, serial);
    let mut st = ctx.st.borrow_mut();
    if st.devices.get(&id).is_some_and(|d| !d.paired() && d.link.is_none() && d.pair_state == 0) {
        st.devices.remove(&id);
    }
    drop(st);
    changed(ctx);
    Ok(())
}

fn udp_socket() -> std::io::Result<UdpSocket> {
    use socket2::{Domain, Protocol, Socket, Type};
    let s = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    s.set_reuse_port(true)?;
    s.set_broadcast(true)?;
    s.bind(&SocketAddr::from(([0, 0, 0, 0], CONFIG.udp_port)).into())?;
    s.set_nonblocking(true)?;
    UdpSocket::from_std(s.into())
}

async fn run() -> Result<(), String> {
    let me = Me::load()?;
    let mut devices = HashMap::new();
    for e in std::fs::read_dir(CONFIG.dir.join("devices")).into_iter().flatten().flatten() {
        let name = e.file_name().to_string_lossy().into_owned();
        if let Some(id) = name.strip_suffix(".json").filter(|id| valid_id(id))
            && let Some(d) = Device::load(id)
        {
            devices.insert(d.id.clone(), d);
        }
    }
    let ctx = Rc::new(Ctx {
        me: RefCell::new(me),
        desktop: Desktop::new(),
        st: RefCell::new(State { devices, clients: Vec::new(), pending: false, clipboard_time: 0, tcp_port: 0, udp: None, answered: HashMap::new() }),
        links: Cell::new(0),
    });

    let mut server = None;
    for port in CONFIG.tcp_ports.clone() {
        if let Ok(l) = TcpListener::bind(("0.0.0.0", port)).await {
            server = Some((l, port));
            break;
        }
    }
    let (server, port) = server.ok_or("no port free in 1716-1764 (is KDE Connect running?)")?;
    ctx.st.borrow_mut().tcp_port = port;
    let udp = Rc::new(udp_socket().map_err(|e| format!("the discovery port {} is taken (is KDE Connect running?): {e}", CONFIG.udp_port))?);
    ctx.st.borrow_mut().udp = Some(udp.clone());
    let _ = std::fs::remove_file(&CONFIG.socket);
    let old = unsafe { libc::umask(0o077) };
    let control = UnixListener::bind(&CONFIG.socket);
    unsafe { libc::umask(old) };
    let control = control.map_err(|e| format!("{}: {e}", CONFIG.socket.display()))?;

    ctx.desktop.start(&ctx).await;
    tokio::task::spawn_local(discovery(ctx.clone(), udp));
    let c = ctx.clone();
    tokio::task::spawn_local(async move {
        loop {
            let alone = !c.st.borrow().devices.values().any(|d| d.paired() && d.link.is_some());
            if alone {
                announce(&c, None);
            }
            tokio::time::sleep(Duration::from_secs(60)).await;
        }
    });
    tokio::task::spawn_local(Desktop::watch_clipboard(ctx.clone()));
    tokio::task::spawn_local(Desktop::watch_players(ctx.clone()));
    let c = ctx.clone();
    tokio::task::spawn_local(async move {
        let mut last = None;
        loop {
            let now = c.desktop.battery();
            if now != last {
                last = now;
                let ids: Vec<String> = c.st.borrow().devices.keys().cloned().collect();
                for id in ids {
                    device::send_battery(&c, &id);
                }
            }
            tokio::time::sleep(Duration::from_secs(60)).await;
        }
    });
    let c = ctx.clone();
    tokio::task::spawn_local(async move {
        while let Ok((tcp, address)) = server.accept().await {
            tokio::task::spawn_local(connected(c.clone(), tcp, address));
        }
    });
    let c = ctx.clone();
    tokio::task::spawn_local(async move {
        while let Ok((stream, _)) = control.accept().await {
            tokio::task::spawn_local(client(c.clone(), stream));
        }
    });

    println!("phone link: {} ({}) on port {port}", ctx.me.borrow().name, ctx.me.borrow().id);
    use tokio::signal::unix::{SignalKind, signal};
    let (mut int, mut term) = (signal(SignalKind::interrupt()).map_err(|e| e.to_string())?, signal(SignalKind::terminate()).map_err(|e| e.to_string())?);
    tokio::select! {
        _ = int.recv() => {}
        _ = term.recv() => {}
    }
    for d in ctx.st.borrow().devices.values() {
        if let Some(l) = &d.link {
            l.close();
        }
    }
    let _ = std::fs::remove_file(&CONFIG.socket);
    Ok(())
}

async fn send(paths: Vec<String>) -> Option<String> {
    let Ok(stream) = UnixStream::connect(&CONFIG.socket).await else { return Some("The phone link is off".into()) };
    let (read, mut write) = stream.into_split();
    let mut read = BufReader::new(read);
    read_line(&mut read).await;
    let _ = write.write_all(&encode(&json!({"do": "send", "paths": paths}))).await;
    let msg = timeout(Duration::from_secs(2), read_line(&mut read)).await.ok().flatten()
        .and_then(|l| serde_json::from_slice::<Value>(&l).ok()).unwrap_or_default();
    msg["error"].as_str().map(String::from)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().expect("a runtime");
    let _inside = rt.enter();
    let local = tokio::task::LocalSet::new();
    match args.first().map(String::as_str) {
        None => {
            if let Err(e) = local.block_on(&rt, run()) {
                eprintln!("{e}");
                std::process::exit(1);
            }
        }
        Some("send") if args.len() > 1 => {
            let paths = args[1..].iter().map(|a| std::path::absolute(a).map_or_else(|_| a.clone(), |p| p.display().to_string())).collect();
            if let Some(error) = local.block_on(&rt, send(paths)) {
                let _ = std::process::Command::new("notify-send").args(["-a", "Phone", "-i", "smartphone", &error,
                    "Turn it on from the phone in the bar, with your phone on the same Wi-Fi"]).status();
                std::process::exit(1);
            }
        }
        _ => {
            eprintln!("phoned | phoned send FILE…");
            std::process::exit(2);
        }
    }
}
