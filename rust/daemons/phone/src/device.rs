use crate::desktop::{COMMANDS, Notice, OnAction, OnClosed};
use crate::protocol::{self, CONFIG, Link, as_int, first_text, now_s, packet, text, truthy, write_atomic};
use crate::{Ctx, changed, report, spawn};
use serde_json::{Map, Value, json};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::LazyLock;
use std::time::Duration;
use tokio::task::AbortHandle;

const PAIR_TIMEOUT: Duration = Duration::from_secs(30);
const FEATURES: &[&str] = &["notifications", "clipboard", "pausemusic", "control"];

pub struct Device {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub cert: Option<Vec<u8>>,
    pub features: BTreeMap<String, bool>,
    pub link: Option<Rc<Link>>,
    incoming: HashSet<String>,
    pub pair_state: u8,
    pair_time: i64,
    pair_timer: Option<AbortHandle>,
    pair_note: u32,
    code: String,
    battery: i64,
    charging: bool,
    network: String,
    signal: i64,
    notes: HashMap<String, u32>,
    call_note: u32,
    ring_note: u32,
    players: Vec<(String, String)>,
    watching: HashSet<String>,
}

pub fn clean(name: &str) -> String {
    static MARKS: LazyLock<regex::Regex> = LazyLock::new(|| regex::Regex::new(r#"["',;:.!?()\[\]<>]"#).unwrap());
    MARKS.replace_all(name, "").trim().chars().take(32).collect()
}

fn path_of(id: &str) -> PathBuf {
    CONFIG.dir.join("devices").join(format!("{id}.json"))
}

impl Device {
    pub fn new(id: &str) -> Device {
        Device {
            id: id.into(), name: id.chars().take(8).collect(), kind: "phone".into(), cert: None,
            features: FEATURES.iter().map(|f| (f.to_string(), true)).collect(), link: None, incoming: HashSet::new(),
            pair_state: 0, pair_time: 0, pair_timer: None, pair_note: 0, code: String::new(),
            battery: -1, charging: false, network: String::new(), signal: -1, notes: HashMap::new(), call_note: 0,
            ring_note: 0, players: Vec::new(), watching: HashSet::new(),
        }
    }

    pub fn paired(&self) -> bool {
        self.pair_state == 3
    }

    fn feature(&self, name: &str) -> bool {
        self.features.get(name).copied().unwrap_or(false)
    }

    pub fn load(id: &str) -> Option<Device> {
        let saved: Value = serde_json::from_slice(&std::fs::read(path_of(id)).ok()?).ok()?;
        let mut d = Device::new(id);
        d.name = text(saved.get("name")?).chars().take(32).collect();
        d.kind = saved.get("type").map_or_else(|| "phone".into(), text);
        d.cert = Some(protocol::der_of_pem(saved["cert"].as_str()?)?);
        for (k, v) in saved["features"].as_object().into_iter().flatten() {
            if FEATURES.contains(&k.as_str()) {
                d.features.insert(k.clone(), truthy(v));
            }
        }
        d.pair_state = 3;
        Some(d)
    }

    fn save(&self) {
        let path = path_of(&self.id);
        if let Some(dir) = path.parent() {
            use std::os::unix::fs::DirBuilderExt;
            let _ = std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir);
        }
        let cert = self.cert.as_deref().map(protocol::pem).unwrap_or_default();
        let data = json!({"name": self.name, "type": self.kind, "cert": cert, "features": self.features});
        let _ = write_atomic(&path, data.to_string().as_bytes());
    }

    fn forget(&self) {
        let _ = std::fs::remove_file(path_of(&self.id));
    }

    pub fn state(&self) -> Value {
        let can: Vec<&str> = [("ring", "kdeconnect.findmyphone.request"), ("ping", "kdeconnect.ping"),
            ("share", "kdeconnect.share.request"), ("clipboard", "kdeconnect.clipboard")]
            .into_iter().filter(|(_, kind)| self.link.is_some() && self.incoming.contains(*kind)).map(|(k, _)| k).collect();
        json!({"id": self.id, "name": self.name, "type": self.kind, "reachable": self.link.is_some(),
            "pairState": self.pair_state, "code": if matches!(self.pair_state, 1 | 2) { self.code.as_str() } else { "" },
            "battery": if self.link.is_some() { self.battery } else { -1 }, "charging": self.charging, "network": self.network,
            "signal": self.signal, "can": can, "features": if self.paired() { json!(self.features) } else { json!({}) }})
    }
}

fn with<R>(ctx: &Ctx, id: &str, f: impl FnOnce(&mut Device) -> R) -> Option<R> {
    ctx.st.borrow_mut().devices.get_mut(id).map(f)
}

fn link(ctx: &Ctx, id: &str) -> Option<Rc<Link>> {
    with(ctx, id, |d| d.link.clone()).flatten()
}

fn name(ctx: &Ctx, id: &str) -> String {
    with(ctx, id, |d| d.name.clone()).unwrap_or_default()
}

pub fn send(ctx: &Ctx, id: &str, kind: &str, body: Value) {
    if let Some(l) = link(ctx, id) {
        l.post(&packet(kind, body));
    }
}

fn notify(ctx: &Rc<Ctx>, n: Notice, keep: impl FnOnce(&Rc<Ctx>, u32) + 'static) {
    let ctx = ctx.clone();
    tokio::task::spawn_local(async move {
        let nid = ctx.desktop.notify(n).await;
        keep(&ctx, nid);
    });
}

fn shown(ctx: &Rc<Ctx>, n: Notice) {
    notify(ctx, n, |_, _| {});
}

fn on_action(f: impl Fn(&Rc<Ctx>, &str) + 'static) -> Option<OnAction> {
    Some(Rc::new(f))
}

fn on_closed(f: impl Fn(&Rc<Ctx>) + 'static) -> Option<OnClosed> {
    Some(Rc::new(f))
}

pub fn attach(ctx: &Rc<Ctx>, id: &str, link: Rc<Link>, identity: &Map<String, Value>) {
    let paired = with(ctx, id, |d| {
        if let Some(old) = d.link.take() {
            old.close();
        }
        d.link = Some(link);
        let n = clean(&identity.get("deviceName").map(text).unwrap_or_default());
        if !n.is_empty() {
            d.name = n;
        }
        d.kind = identity.get("deviceType").map_or_else(|| "phone".into(), text);
        d.incoming = identity.get("incomingCapabilities").and_then(Value::as_array).into_iter().flatten()
            .filter_map(|v| v.as_str().map(String::from)).collect();
        if d.paired() {
            d.save();
        }
        d.paired()
    });
    if paired == Some(true) {
        greet(ctx, id);
    }
}

fn greet(ctx: &Rc<Ctx>, id: &str) {
    send_battery(ctx, id);
    let (clip, control) = with(ctx, id, |d| (d.feature("clipboard"), d.feature("control"))).unwrap_or_default();
    let content = ctx.desktop.clipboard.borrow().clone();
    if clip && !content.is_empty() {
        let stamp = ctx.st.borrow().clipboard_time;
        send(ctx, id, "kdeconnect.clipboard.connect", json!({"content": content, "timestamp": stamp}));
    }
    if control {
        send(ctx, id, "kdeconnect.mousepad.keyboardstate", json!({"state": true}));
        send_commands(ctx, id);
    }
}

pub fn detach(ctx: &Rc<Ctx>, id: &str, serial: u64) {
    let Some(Some(pairing)) = with(ctx, id, |d| {
        if d.link.as_ref().map(|l| l.serial) != Some(serial) {
            return None;
        }
        d.link = None;
        d.watching.clear();
        Some(matches!(d.pair_state, 1 | 2))
    }) else {
        return;
    };
    if pairing {
        pairing_over(ctx, id, false);
    }
    let nids = with(ctx, id, |d| {
        let mut n: Vec<u32> = d.notes.drain().map(|(_, v)| v).collect();
        n.push(d.call_note);
        n
    });
    for nid in nids.unwrap_or_default() {
        ctx.desktop.close_notification(nid);
    }
}

fn make_code(ctx: &Rc<Ctx>, id: &str) {
    let Some(l) = link(ctx, id) else { return };
    let a = ctx.me.borrow_mut().public();
    let b = protocol::public_key(&l.cert);
    let (hi, lo) = if a >= b { (a, b) } else { (b, a) };
    let stamp = with(ctx, id, |d| d.pair_time).unwrap_or(0);
    let mut data = hi;
    data.extend(lo);
    data.extend(stamp.to_string().as_bytes());
    let code: String = openssl::sha::sha256(&data).iter().take(4).map(|b| format!("{b:02X}")).collect();
    with(ctx, id, |d| d.code = code);
    changed(ctx);
}

fn pairing_started(ctx: &Rc<Ctx>, id: &str, state: u8) {
    let (c, i) = (ctx.clone(), id.to_string());
    let timer = tokio::task::spawn_local(async move {
        tokio::time::sleep(PAIR_TIMEOUT).await;
        pairing_timed_out(&c, &i);
    });
    with(ctx, id, |d| {
        d.pair_state = state;
        if let Some(t) = d.pair_timer.replace(timer.abort_handle()) {
            t.abort();
        }
    });
    make_code(ctx, id);
}

fn pairing_timed_out(ctx: &Rc<Ctx>, id: &str) {
    let waiting = with(ctx, id, |d| {
        d.pair_timer = None;
        matches!(d.pair_state, 1 | 2)
    });
    if waiting == Some(true) {
        report(ctx, &format!("{} didn't answer in time", name(ctx, id)));
        pairing_over(ctx, id, false);
    }
}

fn pairing_over(ctx: &Rc<Ctx>, id: &str, paired: bool) {
    let Some(note) = with(ctx, id, |d| {
        if let Some(t) = d.pair_timer.take() {
            t.abort();
        }
        d.code.clear();
        d.pair_state = if paired { 3 } else { 0 };
        if paired {
            d.cert = d.link.as_ref().map(|l| l.cert.clone());
            d.save();
        }
        std::mem::take(&mut d.pair_note)
    }) else {
        return;
    };
    ctx.desktop.close_notification(note);
    if paired {
        greet(ctx, id);
    }
    changed(ctx);
}

pub fn request_pairing(ctx: &Rc<Ctx>, id: &str) -> Result<(), String> {
    let (linked, paired, state) = with(ctx, id, |d| (d.link.is_some(), d.paired(), d.pair_state)).unwrap_or_default();
    if !linked || paired {
        return Err(if linked { "already paired" } else { "not in reach" }.into());
    }
    if state == 2 {
        return accept_pairing(ctx, id);
    }
    let stamp = now_s();
    with(ctx, id, |d| d.pair_time = stamp);
    send(ctx, id, "kdeconnect.pair", json!({"pair": true, "timestamp": stamp}));
    pairing_started(ctx, id, 1);
    Ok(())
}

pub fn accept_pairing(ctx: &Rc<Ctx>, id: &str) -> Result<(), String> {
    if with(ctx, id, |d| d.pair_state != 2 || d.link.is_none()).unwrap_or(true) {
        return Err("it isn't asking to pair".into());
    }
    send(ctx, id, "kdeconnect.pair", json!({"pair": true}));
    pairing_over(ctx, id, true);
    Ok(())
}

pub fn cancel_pairing(ctx: &Rc<Ctx>, id: &str) -> Result<(), String> {
    if with(ctx, id, |d| matches!(d.pair_state, 1 | 2)) == Some(true) {
        send(ctx, id, "kdeconnect.pair", json!({"pair": false}));
        pairing_over(ctx, id, false);
    }
    Ok(())
}

pub fn unpair(ctx: &Rc<Ctx>, id: &str) -> Result<(), String> {
    send(ctx, id, "kdeconnect.pair", json!({"pair": false}));
    unpaired(ctx, id);
    Ok(())
}

fn unpaired(ctx: &Rc<Ctx>, id: &str) {
    let gone = with(ctx, id, |d| {
        d.pair_state = 0;
        d.cert = None;
        d.forget();
        d.link.is_none()
    });
    if gone == Some(true) {
        ctx.st.borrow_mut().devices.remove(id);
    }
    changed(ctx);
}

fn pair_packet(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>) {
    let state = with(ctx, id, |d| d.pair_state).unwrap_or(0);
    if body.get("pair").is_some_and(truthy) {
        if state == 1 {
            pairing_over(ctx, id, true);
        } else if matches!(state, 0 | 3) && body.contains_key("timestamp") {
            if state == 3 {
                unpaired(ctx, id);
            }
            let Some(stamp) = as_int(&body["timestamp"]) else { return };
            if (stamp - now_s()).abs() > 1800 {
                report(ctx, &format!("{}'s clock is too far from this one's to pair", name(ctx, id)));
                return;
            }
            with(ctx, id, |d| d.pair_time = stamp);
            pairing_started(ctx, id, 2);
            ask_to_pair(ctx, id);
        }
    } else if state == 3 {
        unpaired(ctx, id);
    } else if matches!(state, 1 | 2) {
        report(ctx, &format!("{} said no", name(ctx, id)));
        pairing_over(ctx, id, false);
    }
}

fn ask_to_pair(ctx: &Rc<Ctx>, id: &str) {
    let (who, code) = with(ctx, id, |d| (d.name.clone(), d.code.clone())).unwrap_or_default();
    let i = id.to_string();
    let answer = on_action(move |ctx, action| {
        let _ = if action == "accept" { accept_pairing(ctx, &i) } else { cancel_pairing(ctx, &i) };
    });
    let i = id.to_string();
    notify(ctx, Notice {
        key: format!("pair-{id}"), app: "Phone".into(), title: format!("{who} wants to pair"),
        body: format!("Code {code}: the same on the phone?"), urgent: true,
        actions: vec![("accept".into(), "Pair".into()), ("reject".into(), "Reject".into())], on_action: answer,
        ..Default::default()
    }, move |ctx, nid| {
        with(ctx, &i, |d| d.pair_note = nid);
    });
}

pub async fn handle(ctx: &Rc<Ctx>, id: &str, pkt: Value) {
    let kind = pkt["type"].as_str().unwrap_or("").to_string();
    let Some(body) = pkt["body"].as_object().cloned() else { return };
    if kind == "kdeconnect.pair" {
        return pair_packet(ctx, id, &body);
    }
    if kind == "kdeconnect.identity" || with(ctx, id, |d| d.paired()) != Some(true) {
        return;
    }
    let _ = match kind.as_str() {
        "kdeconnect.ping" => got_ping(ctx, id, &body),
        "kdeconnect.battery" => got_battery(ctx, id, &body),
        "kdeconnect.connectivity_report" => got_network(ctx, id, &body),
        "kdeconnect.clipboard" | "kdeconnect.clipboard.connect" => got_clipboard(ctx, id, &body, &kind),
        "kdeconnect.notification" => got_notification(ctx, id, &body, &pkt),
        "kdeconnect.telephony" => got_call(ctx, id, &body).await,
        "kdeconnect.findmyphone.request" => got_find(ctx, id),
        "kdeconnect.share.request" => got_share(ctx, id, &body, &pkt),
        "kdeconnect.mousepad.request" => got_mouse(ctx, id, &body),
        "kdeconnect.runcommand.request" => got_command(ctx, id, &body),
        "kdeconnect.systemvolume.request" => got_volume(ctx, id, &body),
        "kdeconnect.mpris.request" => got_media(ctx, id, &body).await,
        _ => None,
    };
}

fn got_ping(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>) -> Option<()> {
    shown(ctx, Notice {
        key: format!("ping-{id}"), app: name(ctx, id), title: "Ping".into(),
        body: first_text(body, &["message"], "Hello from the phone"), ..Default::default()
    });
    Some(())
}

fn got_battery(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>) -> Option<()> {
    let charge = body.get("currentCharge").map_or(Some(-1), as_int)?.clamp(-1, 100);
    let charging = body.get("isCharging").is_some_and(truthy);
    with(ctx, id, |d| {
        d.battery = charge;
        d.charging = charging;
    });
    changed(ctx);
    Some(())
}

fn got_network(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>) -> Option<()> {
    let first = body.get("signalStrengths").and_then(Value::as_object).and_then(|s| s.values().next()).filter(|f| truthy(f));
    let (network, signal) = match first {
        Some(f) => {
            let f = f.as_object()?;
            let kind: String = f.get("networkType").map(text).unwrap_or_default().chars().take(12).collect();
            let net = if matches!(kind.to_lowercase().as_str(), "unknown" | "") { String::new() } else { kind };
            (net, f.get("signalStrength").map_or(Some(-1), as_int)?.clamp(-1, 4))
        }
        None => (String::new(), -1),
    };
    with(ctx, id, |d| {
        d.network = network;
        d.signal = signal;
    });
    changed(ctx);
    Some(())
}

fn got_clipboard(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>, kind: &str) -> Option<()> {
    let content = body.get("content")?.as_str().filter(|c| !c.is_empty())?;
    if with(ctx, id, |d| d.feature("clipboard")) != Some(true) {
        return None;
    }
    if kind == "kdeconnect.clipboard.connect" {
        let stamp = body.get("timestamp").filter(|v| truthy(v)).map_or(Some(0), as_int)?;
        if stamp <= ctx.st.borrow().clipboard_time {
            return None;
        }
    }
    ctx.desktop.set_clipboard(content);
    Some(())
}

fn got_notification(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>, pkt: &Value) -> Option<()> {
    if with(ctx, id, |d| d.feature("notifications")) != Some(true) {
        return None;
    }
    let key = body.get("id").map(text).filter(|k| !k.is_empty())?;
    if body.get("isCancel").is_some_and(truthy) {
        let nid = with(ctx, id, |d| d.notes.remove(&key)).flatten().unwrap_or(0);
        ctx.desktop.close_notification(nid);
        return Some(());
    }
    if body.get("silent").is_some_and(truthy) || body.get("appName").map(text).as_deref() == Some("KDE Connect") {
        return None;
    }
    let (c, i, b, p) = (ctx.clone(), id.to_string(), body.clone(), pkt.clone());
    tokio::task::spawn_local(async move { show_notification(&c, &i, key, b, p).await });
    Some(())
}

async fn show_notification(ctx: &Rc<Ctx>, id: &str, key: String, body: Map<String, Value>, pkt: Value) {
    let mut image = None;
    let digest = body.get("payloadHash").map(text).unwrap_or_default();
    let hashlike = (8..=64).contains(&digest.len()) && digest.chars().all(|c| c.is_ascii_hexdigit());
    if truthy(&pkt["payloadTransferInfo"]) && hashlike {
        let home = std::env::var("HOME").unwrap_or_default();
        let cache = std::env::var("XDG_CACHE_HOME").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| format!("{home}/.cache"));
        let dir = Path::new(&cache).join("vyntaris/phone-icons");
        let _ = std::fs::create_dir_all(&dir);
        let path = dir.join(format!("{digest}.png"));
        let mut ok = path.exists();
        let tls = ctx.me.borrow().client_context();
        if !ok && let (Some(l), Ok(tls)) = (link(ctx, id), tls) {
            ok = protocol::download(&tls, &l, &pkt, &path).await.is_ok();
        }
        if ok {
            image = Some(path.display().to_string());
        }
    }
    let actions: Vec<(String, String)> = body.get("actions").and_then(Value::as_array).into_iter().flatten()
        .filter_map(Value::as_str).take(3).map(|a| (format!("a:{a}"), a.to_string())).collect();
    let (i, k) = (id.to_string(), key.clone());
    let acted = on_action(move |ctx, action| {
        if let Some(a) = action.strip_prefix("a:") {
            send(ctx, &i, "kdeconnect.notification.action", json!({"key": k, "action": a}));
        }
    });
    let (i, k, clearable) = (id.to_string(), key.clone(), body.get("isClearable").is_some_and(truthy));
    let dismissed = on_closed(move |ctx| {
        with(ctx, &i, |d| d.notes.remove(&k));
        if clearable {
            send(ctx, &i, "kdeconnect.notification.request", json!({"cancel": k}));
        }
    });
    let who = name(ctx, id);
    let app = first_text(&body, &["appName"], &who);
    let title = first_text(&body, &["title", "ticker"], &app);
    let replaces = with(ctx, id, |d| d.notes.get(&key).copied()).flatten().unwrap_or(0);
    let i = id.to_string();
    notify(ctx, Notice {
        key: format!("note-{id}-{key}"), app, title, body: body.get("text").map(text).unwrap_or_default(), image, actions,
        replaces, on_action: acted, on_closed: dismissed, ..Default::default()
    }, move |ctx, nid| {
        with(ctx, &i, |d| d.notes.insert(key, nid));
    });
}

async fn got_call(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>) -> Option<()> {
    let event = body.get("event").and_then(Value::as_str).unwrap_or("");
    let who = first_text(body, &["contactName", "phoneNumber"], "Unknown number");
    let pause = with(ctx, id, |d| d.feature("pausemusic")).unwrap_or(false);
    if body.get("isCancel").is_some_and(truthy) {
        let nid = with(ctx, id, |d| std::mem::take(&mut d.call_note)).unwrap_or(0);
        ctx.desktop.close_notification(nid);
        if pause {
            ctx.desktop.resume_after_call().await;
        }
        return Some(());
    }
    let device = name(ctx, id);
    if matches!(event, "ringing" | "talking") {
        if pause && ctx.desktop.paused.borrow().is_empty() {
            ctx.desktop.pause_for_call().await;
        }
        if event == "ringing" {
            let i = id.to_string();
            let mute = on_action(move |ctx, _| send(ctx, &i, "kdeconnect.telephony.request_mute", json!({})));
            let i = id.to_string();
            notify(ctx, Notice {
                key: format!("call-{id}"), app: device, title: format!("Call from {who}"), body: "On your phone".into(),
                icon: "call", urgent: true, actions: vec![("mute".into(), "Silence".into())],
                replaces: with(ctx, id, |d| d.call_note).unwrap_or(0), on_action: mute, ..Default::default()
            }, move |ctx, nid| {
                with(ctx, &i, |d| d.call_note = nid);
            });
        }
    } else if event == "missedCall" {
        shown(ctx, Notice { key: format!("missed-{id}"), app: device, title: format!("Missed call from {who}"), icon: "call", ..Default::default() });
    }
    Some(())
}

fn got_find(ctx: &Rc<Ctx>, id: &str) -> Option<()> {
    ctx.desktop.ring(true);
    let i = id.to_string();
    notify(ctx, Notice {
        key: format!("find-{id}"), app: name(ctx, id), title: "Your phone is looking for this computer".into(), urgent: true,
        actions: vec![("found".into(), "Found it".into())], replaces: with(ctx, id, |d| d.ring_note).unwrap_or(0),
        on_action: on_action(|ctx, _| ctx.desktop.ring(false)), on_closed: on_closed(|ctx| ctx.desktop.ring(false)),
        ..Default::default()
    }, move |ctx, nid| {
        with(ctx, &i, |d| d.ring_note = nid);
    });
    Some(())
}

fn got_share(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>, pkt: &Value) -> Option<()> {
    let who = name(ctx, id);
    if body.contains_key("filename") && truthy(&pkt["payloadTransferInfo"]) {
        let (c, i, b, p) = (ctx.clone(), id.to_string(), body.clone(), pkt.clone());
        spawn(ctx, async move { receive_file(&c, &i, &b, &p).await });
    } else if let Some(t) = body.get("text").and_then(Value::as_str) {
        ctx.desktop.set_clipboard(t);
        shown(ctx, Notice {
            key: format!("text-{id}"), app: who, title: "Text from your phone, copied".into(), body: t.chars().take(200).collect(),
            ..Default::default()
        });
    } else if let Some(url) = body.get("url").and_then(Value::as_str) {
        static LINK: LazyLock<regex::Regex> = LazyLock::new(|| regex::Regex::new(r"^(https?|geo|tel|mailto):").unwrap());
        if LINK.is_match(url) {
            let u = url.to_string();
            shown(ctx, Notice {
                key: format!("url-{id}"), app: who, title: "A link from your phone".into(), body: url.chars().take(200).collect(),
                actions: vec![("open".into(), "Open".into())], on_action: on_action(move |ctx, _| ctx.desktop.open(&u)),
                ..Default::default()
            });
        }
    }
    Some(())
}

fn split_ext(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(i) if name[..i].chars().any(|c| c != '.') => (&name[..i], &name[i..]),
        _ => (name, ""),
    }
}

async fn receive_file(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>, pkt: &Value) -> Result<(), String> {
    let given = text(&body["filename"]);
    let base = given.rsplit('/').next().unwrap_or("").trim().trim_start_matches('.');
    let file: String = if base.is_empty() { "file".into() } else { base.chars().take(200).collect() };
    let folder = ctx.desktop.downloads().await;
    let (stem, ext) = split_ext(&file);
    let mut dest = folder.join(format!("{stem}{ext}"));
    let mut n = 1;
    while dest.exists() {
        n += 1;
        dest = folder.join(format!("{stem} ({n}){ext}"));
    }
    let l = link(ctx, id).ok_or("the phone went")?;
    let tls = ctx.me.borrow().client_context()?;
    protocol::download(&tls, &l, pkt, &dest).await?;
    let (file, dir) = (dest.display().to_string(), folder.display().to_string());
    shown(ctx, Notice {
        key: format!("file-{id}"), app: name(ctx, id), title: "A file from your phone".into(),
        body: dest.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default(),
        actions: vec![("open".into(), "Open".into()), ("folder".into(), "Show in Files".into())],
        on_action: on_action(move |ctx, a| ctx.desktop.open(if a == "open" { &file } else { &dir })), ..Default::default()
    });
    Ok(())
}

fn got_mouse(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>) -> Option<()> {
    if with(ctx, id, |d| d.feature("control")) == Some(true) {
        ctx.desktop.mouse(body)?;
    }
    Some(())
}

fn send_commands(ctx: &Rc<Ctx>, id: &str) {
    let listing: Map<String, Value> = COMMANDS.iter().map(|(k, n, _)| (k.to_string(), json!({"name": n, "command": n}))).collect();
    send(ctx, id, "kdeconnect.runcommand", json!({"commandList": Value::Object(listing).to_string(), "canAddCommand": false}));
}

fn got_command(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>) -> Option<()> {
    if with(ctx, id, |d| d.feature("control")) != Some(true) {
        return None;
    }
    if body.get("requestCommandList").is_some_and(truthy) {
        send_commands(ctx, id);
    } else if let Some(k) = body.get("key").and_then(Value::as_str) {
        ctx.desktop.command(k);
    }
    Some(())
}

fn got_volume(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>) -> Option<()> {
    if with(ctx, id, |d| d.feature("control")) != Some(true) {
        return None;
    }
    let named = body.contains_key("name");
    if named {
        ctx.desktop.set_sink(&text(&body["name"]), body.get("volume"), body.get("muted"), body.get("enabled").is_some_and(truthy))?;
    }
    let (c, i) = (ctx.clone(), id.to_string());
    tokio::task::spawn_local(async move {
        tokio::time::sleep(Duration::from_millis(if named { 300 } else { 0 })).await;
        let sinks: Vec<Value> = c.desktop.sinks().await.into_iter().map(|s| json!({"name": s["name"], "description": s["description"],
            "muted": s["muted"], "volume": s["volume"], "maxVolume": 100, "enabled": s["default"]})).collect();
        send(&c, &i, "kdeconnect.systemvolume", json!({"sinkList": sinks}));
    });
    Some(())
}

async fn got_media(ctx: &Rc<Ctx>, id: &str, body: &Map<String, Value>) -> Option<()> {
    if with(ctx, id, |d| d.feature("control")) != Some(true) {
        return None;
    }
    if body.get("requestPlayerList").is_some_and(truthy) {
        let players = ctx.desktop.players().await;
        let names: Vec<&String> = players.iter().map(|(n, _)| n).collect();
        send(ctx, id, "kdeconnect.mpris", json!({"playerList": names, "supportAlbumArtPayload": false}));
        with(ctx, id, |d| d.players = players);
    }
    let player = body.get("player")?.as_str()?.to_string();
    let bus_name = with(ctx, id, |d| d.players.iter().find(|(n, _)| *n == player).map(|(_, b)| b.clone())).flatten()?;
    if ["action", "setVolume", "SetPosition", "Seek"].iter().any(|k| body.contains_key(*k)) {
        ctx.desktop.player_do(&bus_name, body.get("action"), body.get("setVolume"), body.get("SetPosition"), body.get("Seek")).await;
    }
    let flag = |k: &str| body.get(k).is_some_and(truthy);
    if flag("requestNowPlaying") || flag("requestVolume") || body.contains_key("action") {
        with(ctx, id, |d| d.watching.insert(player.clone()));
        send_player(ctx, id, &player).await;
    }
    Some(())
}

async fn send_player(ctx: &Rc<Ctx>, id: &str, player: &str) {
    let bus_name = with(ctx, id, |d| d.players.iter().find(|(n, _)| n == player).map(|(_, b)| b.clone())).flatten().unwrap_or_default();
    if let Some(mut state) = ctx.desktop.player_state(&bus_name).await {
        state.insert("player".into(), json!(player));
        send(ctx, id, "kdeconnect.mpris", Value::Object(state));
    }
}

pub async fn players_changed(ctx: &Rc<Ctx>, sender: &str) {
    let watched: Vec<(String, String, String)> = ctx.st.borrow().devices.values().filter(|d| d.link.is_some()).flat_map(|d| {
        d.watching.iter().filter_map(|w| d.players.iter().find(|(n, _)| n == w)).map(|(n, b)| (d.id.clone(), n.clone(), b.clone())).collect::<Vec<_>>()
    }).collect();
    for (id, player, bus_name) in watched {
        if !sender.is_empty() && ctx.desktop.owner(&bus_name).await == sender {
            send_player(ctx, &id, &player).await;
        }
    }
}

pub fn send_battery(ctx: &Rc<Ctx>, id: &str) {
    if with(ctx, id, |d| d.paired() && d.link.is_some()) != Some(true) {
        return;
    }
    if let Some((charge, charging)) = ctx.desktop.battery() {
        send(ctx, id, "kdeconnect.battery", json!({"currentCharge": charge, "isCharging": charging, "thresholdEvent": 0}));
    }
}

pub fn clipboard_changed(ctx: &Rc<Ctx>, id: &str, text: &str) {
    if with(ctx, id, |d| d.paired() && d.link.is_some() && d.feature("clipboard")) == Some(true) {
        send(ctx, id, "kdeconnect.clipboard", json!({"content": text}));
    }
}

fn need(ctx: &Ctx, id: &str, kind: &str) -> Result<(), String> {
    let (paired, linked, can, who) = with(ctx, id, |d| (d.paired(), d.link.is_some(), d.incoming.contains(kind), d.name.clone()))
        .ok_or("no such phone")?;
    if !paired {
        return Err("not paired".into());
    }
    if !linked {
        return Err(format!("{who} isn't in reach"));
    }
    if !can {
        return Err(format!("{who} can't do that"));
    }
    Ok(())
}

pub fn ring(ctx: &Rc<Ctx>, id: &str) -> Result<(), String> {
    need(ctx, id, "kdeconnect.findmyphone.request")?;
    send(ctx, id, "kdeconnect.findmyphone.request", json!({}));
    Ok(())
}

pub fn ping(ctx: &Rc<Ctx>, id: &str) -> Result<(), String> {
    need(ctx, id, "kdeconnect.ping")?;
    send(ctx, id, "kdeconnect.ping", json!({}));
    Ok(())
}

pub fn send_clipboard(ctx: &Rc<Ctx>, id: &str) -> Result<(), String> {
    need(ctx, id, "kdeconnect.clipboard")?;
    let (c, i) = (ctx.clone(), id.to_string());
    tokio::task::spawn_local(async move {
        let text = if c.desktop.fake.is_some() {
            c.desktop.clipboard.borrow().clone()
        } else {
            c.desktop.output(&["wl-paste", "--no-newline", "--type", "text"]).await
        };
        if !text.is_empty() {
            send(&c, &i, "kdeconnect.clipboard", json!({"content": text}));
        }
    });
    Ok(())
}

pub async fn share(ctx: &Rc<Ctx>, id: &str, paths: &[PathBuf]) -> Result<(), String> {
    need(ctx, id, "kdeconnect.share.request")?;
    let total: u64 = paths.iter().map(|p| std::fs::metadata(p).map_or(0, |m| m.len())).sum();
    for p in paths {
        let modified = std::fs::metadata(p).and_then(|m| m.modified()).ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map_or(0, |d| d.as_millis() as i64);
        let pkt = packet("kdeconnect.share.request", json!({
            "filename": p.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default(), "open": false,
            "numberOfFiles": paths.len(), "totalPayloadSize": total, "lastModified": modified, "creationTime": modified}));
        let l = link(ctx, id).ok_or("the phone went")?;
        let tls = ctx.me.borrow().server_context(&l.cert)?;
        protocol::upload(tls, &l, pkt, p).await?;
    }
    let what = if paths.len() == 1 {
        paths[0].file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default()
    } else {
        format!("{} files", paths.len())
    };
    shown(ctx, Notice { key: format!("sent-{id}"), app: "Phone".into(), title: format!("Sent to {}", name(ctx, id)), body: what, ..Default::default() });
    Ok(())
}

pub async fn pick(ctx: &Rc<Ctx>, id: &str) -> Result<(), String> {
    need(ctx, id, "kdeconnect.share.request")?;
    let paths: Vec<PathBuf> = ctx.desktop.pick_files(&format!("Send to {}", name(ctx, id))).await
        .into_iter().map(PathBuf::from).filter(|p| p.is_file()).collect();
    if !paths.is_empty() {
        share(ctx, id, &paths).await?;
    }
    Ok(())
}

pub fn set_feature(ctx: &Rc<Ctx>, id: &str, feature: &str, on: bool) -> Result<(), String> {
    with(ctx, id, |d| {
        if !FEATURES.contains(&feature) || !d.paired() {
            return Err("not a feature".to_string());
        }
        d.features.insert(feature.into(), on);
        d.save();
        Ok(())
    })
    .unwrap_or_else(|| Err("no such phone".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_kept_clean() {
        assert_eq!(clean("Den: PC!"), "Den PC");
        assert_eq!(clean("  <Ana's> phone (5G)  "), "Anas phone 5G");
        assert_eq!(clean(&"x".repeat(40)).len(), 32);
    }

    #[test]
    fn extensions_as_python_splits_them() {
        assert_eq!(split_ext("photo.jpg"), ("photo", ".jpg"));
        assert_eq!(split_ext("archive.tar.gz"), ("archive.tar", ".gz"));
        assert_eq!(split_ext("README"), ("README", ""));
        assert_eq!(split_ext("file"), ("file", ""));
    }
}
