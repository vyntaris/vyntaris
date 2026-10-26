use crate::Ctx;
use crate::protocol::{as_float, as_int, truthy};
use crate::wayland::{BTN_LEFT, BTN_MIDDLE, BTN_RIGHT, VirtualPointer};
use base64::Engine;
use futures_util::StreamExt;
use serde_json::{Map, Value, json};
use std::cell::{OnceCell, RefCell};
use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::rc::Rc;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use zbus::zvariant::{ObjectPath, OwnedValue, Value as V};

const NOTIFY: (&str, &str, &str) = ("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications");
const MPRIS: &str = "org.mpris.MediaPlayer2.";
const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";
const PROPS: &str = "org.freedesktop.DBus.Properties";
const PORTAL: &str = "org.freedesktop.portal.Desktop";
const SOUNDS: &[&str] = &["/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
    "/etc/xdg/quickshell/vyntaris/assets/sounds/notification-urgent.wav"];

pub const COMMANDS: &[(&str, &str, &[&str])] = &[
    ("lock", "Lock the screen", &["loginctl", "lock-session"]),
    ("sleep", "Sleep", &["systemctl", "suspend"]),
    ("mute", "Mute or unmute", &["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]),
    ("screenshot", "Take a screenshot", &["qs", "-c", "vyntaris", "ipc", "call", "screenshot", "screen"]),
];

fn special_key(n: i64) -> Option<String> {
    let named = ["BackSpace", "Tab", "Return", "Left", "Up", "Right", "Down", "Prior", "Next", "Home", "End", "Return",
        "Delete", "Escape", "Sys_Req", "Scroll_Lock", "Control_L", "Alt_L", "Shift_L", "Super_L"];
    match n {
        1..=20 => Some(named[n as usize - 1].to_string()),
        21..=32 => Some(format!("F{}", n - 20)),
        _ => None,
    }
}

pub type OnAction = Rc<dyn Fn(&Rc<Ctx>, &str)>;
pub type OnClosed = Rc<dyn Fn(&Rc<Ctx>)>;
type Answers = (Option<OnAction>, Option<OnClosed>);

#[derive(Default)]
pub struct Notice {
    pub key: String,
    pub app: String,
    pub title: String,
    pub body: String,
    pub icon: &'static str,
    pub image: Option<String>,
    pub actions: Vec<(String, String)>,
    pub urgent: bool,
    pub replaces: u32,
    pub on_action: Option<OnAction>,
    pub on_closed: Option<OnClosed>,
}

pub struct Desktop {
    pub fake: Option<PathBuf>,
    bus: OnceCell<zbus::Connection>,
    pointer: RefCell<VirtualPointer>,
    notes: RefCell<HashMap<u32, Answers>>,
    alarm: RefCell<Option<Child>>,
    pub paused: RefCell<Vec<String>>,
    pub clipboard: RefCell<String>,
}

fn plain<'a>(v: &'a V<'a>) -> &'a V<'a> {
    match v {
        V::Value(inner) => plain(inner),
        other => other,
    }
}

fn v_str(v: &V) -> String {
    match plain(v) {
        V::Str(s) => s.to_string(),
        V::ObjectPath(p) => p.to_string(),
        _ => String::new(),
    }
}

fn v_i64(v: &V) -> i64 {
    match plain(v) {
        V::U8(n) => *n as i64,
        V::I16(n) => *n as i64,
        V::U16(n) => *n as i64,
        V::I32(n) => *n as i64,
        V::U32(n) => *n as i64,
        V::I64(n) => *n,
        V::U64(n) => *n as i64,
        V::F64(n) => *n as i64,
        _ => 0,
    }
}

fn v_f64(v: &V) -> Option<f64> {
    match plain(v) {
        V::F64(n) => Some(*n),
        V::Str(_) | V::Bool(_) => None,
        other => Some(v_i64(other) as f64),
    }
}

fn v_bool(v: &V) -> bool {
    matches!(plain(v), V::Bool(true))
}

fn v_strs(v: &V) -> Vec<String> {
    match plain(v) {
        V::Array(a) => a.iter().map(v_str).collect(),
        V::Str(s) => vec![s.to_string()],
        _ => Vec::new(),
    }
}

fn v_dict<'a>(v: &'a V<'a>) -> HashMap<String, &'a V<'a>> {
    match plain(v) {
        V::Dict(d) => d.iter().map(|(k, v)| (v_str(k), v)).collect(),
        _ => HashMap::new(),
    }
}

pub fn which(name: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(name).is_file()))
}

impl Desktop {
    pub fn new() -> Desktop {
        Desktop {
            fake: std::env::var_os("VYNTARIS_PHONE_FAKE_DESKTOP").filter(|v| !v.is_empty()).map(PathBuf::from),
            bus: OnceCell::new(),
            pointer: RefCell::new(VirtualPointer::new()),
            notes: RefCell::new(HashMap::new()),
            alarm: RefCell::new(None),
            paused: RefCell::new(Vec::new()),
            clipboard: RefCell::new(String::new()),
        }
    }

    pub async fn start(&self, ctx: &Rc<Ctx>) {
        if self.fake.is_some() {
            return;
        }
        let Ok(bus) = zbus::Connection::session().await else {
            eprintln!("phone link: no session bus: no notifications, players or file chooser");
            return;
        };
        let _ = self.bus.set(bus.clone());
        for member in ["ActionInvoked", "NotificationClosed"] {
            let ctx = ctx.clone();
            let Some(mut stream) = signals(&bus, NOTIFY.2, member, Some(NOTIFY.1)).await else { continue };
            tokio::task::spawn_local(async move {
                while let Some(Ok(msg)) = stream.next().await {
                    if member == "ActionInvoked" {
                        let Ok((nid, action)) = msg.body().deserialize::<(u32, String)>() else { continue };
                        let cb = ctx.desktop.notes.borrow().get(&nid).and_then(|n| n.0.clone());
                        if let Some(cb) = cb {
                            cb(&ctx, &action);
                        }
                    } else {
                        let Ok((nid, reason)) = msg.body().deserialize::<(u32, u32)>() else { continue };
                        let note = ctx.desktop.notes.borrow_mut().remove(&nid);
                        if let Some((_, Some(cb))) = note.filter(|_| reason == 2) {
                            cb(&ctx);
                        }
                    }
                }
            });
        }
    }

    fn record(&self, kind: &str, args: Value) {
        let Some(path) = &self.fake else { return };
        let mut entry = Map::new();
        entry.insert("do".into(), json!(kind));
        if let Value::Object(a) = args {
            entry.extend(a);
        }
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
            let _ = f.write_all(format!("{}\n", Value::Object(entry)).as_bytes());
        }
    }

    pub fn run(&self, cmd: &[&str]) {
        if self.fake.is_some() {
            return self.record("run", json!({"cmd": cmd}));
        }
        let _ = Command::new(cmd[0]).args(&cmd[1..]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null())
            .process_group(0).spawn();
    }

    pub async fn output(&self, cmd: &[&str]) -> String {
        let run = Command::new(cmd[0]).args(&cmd[1..]).stdin(Stdio::null()).stderr(Stdio::null()).kill_on_drop(true).output();
        match tokio::time::timeout(Duration::from_secs(5), run).await {
            Ok(Ok(out)) if out.status.success() => String::from_utf8_lossy(&out.stdout).into_owned(),
            _ => String::new(),
        }
    }

    async fn call<B>(&self, dest: &str, path: &str, iface: &str, method: &str, body: &B) -> Option<zbus::Message>
    where
        B: serde::ser::Serialize + zbus::zvariant::DynamicType,
    {
        self.bus.get()?.call_method(Some(dest), path, Some(iface), method, body).await.ok()
    }

    pub async fn notify(&self, n: Notice) -> u32 {
        let ids: Vec<&str> = n.actions.iter().map(|(a, _)| a.as_str()).collect();
        if self.fake.is_some() {
            self.record("notify", json!({"key": n.key, "app": n.app, "title": n.title, "body": n.body, "actions": ids}));
            return 0;
        }
        let mut hints: HashMap<&str, V> = HashMap::new();
        hints.insert("urgency", V::U8(if n.urgent { 2 } else { 1 }));
        hints.insert("x-vyntaris-phone", V::Bool(true));
        if let Some(image) = &n.image {
            hints.insert("image-path", V::from(image.as_str()));
        }
        let flat: Vec<&str> = n.actions.iter().flat_map(|(a, l)| [a.as_str(), l.as_str()]).collect();
        let icon = if n.icon.is_empty() { "smartphone" } else { n.icon };
        let body = (n.app.as_str(), n.replaces, icon, n.title.as_str(), n.body.as_str(), flat, hints, -1i32);
        let Some(reply) = self.call(NOTIFY.0, NOTIFY.1, NOTIFY.2, "Notify", &body).await else { return 0 };
        let nid = reply.body().deserialize::<u32>().unwrap_or(0);
        if nid != 0 {
            self.notes.borrow_mut().insert(nid, (n.on_action, n.on_closed));
        }
        nid
    }

    pub fn close_notification(&self, nid: u32) {
        self.notes.borrow_mut().remove(&nid);
        if self.fake.is_some() || nid == 0 {
            return;
        }
        if let Some(bus) = self.bus.get().cloned() {
            tokio::task::spawn_local(async move {
                let _ = bus.call_method(Some(NOTIFY.0), NOTIFY.1, Some(NOTIFY.2), "CloseNotification", &(nid,)).await;
            });
        }
    }

    pub fn set_clipboard(&self, text: &str) {
        *self.clipboard.borrow_mut() = text.to_string();
        if self.fake.is_some() {
            return self.record("clipboard", json!({"text": text}));
        }
        self.run(&["wl-copy", "--", text]);
    }

    pub async fn watch_clipboard(ctx: Rc<Ctx>) {
        if ctx.desktop.fake.is_some() {
            return;
        }
        loop {
            let child = Command::new("wl-paste").args(["--type", "text", "--watch", "sh", "-c", "base64 -w0; echo"])
                .stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).kill_on_drop(true).spawn();
            if let Ok(mut child) = child {
                if let Some(out) = child.stdout.take() {
                    let mut lines = BufReader::new(out).lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        let Ok(raw) = base64::engine::general_purpose::STANDARD.decode(line.trim()) else { continue };
                        let Ok(text) = String::from_utf8(raw) else { continue };
                        if !text.is_empty() && text != *ctx.desktop.clipboard.borrow() {
                            *ctx.desktop.clipboard.borrow_mut() = text.clone();
                            crate::clipboard_changed(&ctx, &text);
                        }
                    }
                }
                let _ = child.wait().await;
            }
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    }

    fn pointer_do(&self, what: &str, args: Value) {
        if self.fake.is_some() {
            return self.record("pointer", json!({"what": what, "args": args}));
        }
        let a = |i: usize| args[i].as_f64().unwrap_or(0.0);
        let mut p = self.pointer.borrow_mut();
        let _ = match what {
            "move" => p.move_by(a(0), a(1)),
            "scroll" => p.scroll(a(0), a(1)),
            "click" => p.click(a(0) as u32, a(1) as u32),
            _ => p.press(a(0) as u32, args[1].as_bool().unwrap_or(false)),
        };
    }

    pub fn mouse(&self, body: &Map<String, Value>) -> Option<()> {
        let flag = |k: &str| body.get(k).is_some_and(truthy);
        let num = |k: &str| body.get(k).map_or(Some(0.0), as_float);
        if flag("singleclick") {
            self.pointer_do("click", json!([BTN_LEFT, 1]));
        } else if flag("doubleclick") {
            self.pointer_do("click", json!([BTN_LEFT, 2]));
        } else if flag("middleclick") {
            self.pointer_do("click", json!([BTN_MIDDLE, 1]));
        } else if flag("rightclick") {
            self.pointer_do("click", json!([BTN_RIGHT, 1]));
        } else if flag("singlehold") {
            self.pointer_do("press", json!([BTN_LEFT, true]));
        } else if flag("singlerelease") {
            self.pointer_do("press", json!([BTN_LEFT, false]));
        } else if flag("scroll") {
            self.pointer_do("scroll", json!([-num("dx")?, -num("dy")?]));
        } else if body.contains_key("dx") || body.contains_key("dy") {
            self.pointer_do("move", json!([num("dx")?, num("dy")?]));
        }
        let key = body.get("key").map(crate::protocol::text).filter(|_| body.get("key").is_some_and(truthy)).unwrap_or_default();
        let special = body.get("specialKey").filter(|v| truthy(v)).map_or(Some(0), as_int)?;
        let mods: Vec<&str> = [("ctrl", "ctrl"), ("alt", "alt"), ("shift", "shift"), ("logo", "super")]
            .into_iter().filter(|(_, f)| flag(f)).map(|(m, _)| m).collect();
        let keysym = special_key(special);
        if !key.is_empty() || keysym.is_some() {
            self.keys(&key, keysym, &mods);
        }
        Some(())
    }

    fn keys(&self, text: &str, keysym: Option<String>, mods: &[&str]) {
        let mut cmd: Vec<String> = vec!["wtype".into()];
        for m in mods {
            cmd.extend(["-M".into(), m.to_string()]);
        }
        if let Some(k) = keysym {
            cmd.extend(["-k".into(), k]);
        } else if !text.is_empty() {
            if mods.is_empty() {
                cmd.extend(["--".into(), text.into()]);
            } else {
                for ch in text.chars() {
                    cmd.extend(["-k".into(), ch.to_string()]);
                }
            }
        }
        for m in mods.iter().rev() {
            cmd.extend(["-m".into(), m.to_string()]);
        }
        if self.fake.is_some() {
            return self.record("keys", json!({"cmd": cmd}));
        }
        if which("wtype") {
            self.run(&cmd.iter().map(String::as_str).collect::<Vec<_>>());
        }
    }

    pub async fn sinks(&self) -> Vec<Value> {
        if self.fake.is_some() {
            return vec![json!({"name": "speakers", "description": "Speakers", "volume": 40, "muted": false, "default": true})];
        }
        let Ok(sinks) = serde_json::from_str::<Value>(&self.output(&["pactl", "-f", "json", "list", "sinks"]).await) else {
            return Vec::new();
        };
        let default = self.output(&["pactl", "get-default-sink"]).await.trim().to_string();
        sinks.as_array().into_iter().flatten().filter_map(|s| {
            let name = s["name"].as_str()?;
            let pct = s["volume"].as_object().and_then(|v| v.values().next())
                .and_then(|c| c["value_percent"].as_str()).and_then(|p| p.trim_end_matches('%').parse::<i64>().ok()).unwrap_or(0);
            Some(json!({"name": name, "description": s["description"].as_str().unwrap_or(name), "volume": pct,
                "muted": truthy(&s["mute"]), "default": name == default}))
        }).collect()
    }

    pub fn set_sink(&self, name: &str, volume: Option<&Value>, muted: Option<&Value>, default: bool) -> Option<()> {
        if name.is_empty() || !name.chars().all(|c| c.is_alphanumeric() || "_.:-".contains(c)) {
            return Some(());
        }
        if let Some(v) = volume.filter(|v| !v.is_null()) {
            let pct = format!("{}%", as_int(v)?.clamp(0, 100));
            self.run(&["pactl", "set-sink-volume", name, &pct]);
        }
        if let Some(m) = muted.filter(|v| !v.is_null()) {
            self.run(&["pactl", "set-sink-mute", name, if truthy(m) { "1" } else { "0" }]);
        }
        if default {
            self.run(&["pactl", "set-default-sink", name]);
        }
        Some(())
    }

    pub async fn players(&self) -> Vec<(String, String)> {
        if self.fake.is_some() {
            return vec![("Music".into(), "org.mpris.MediaPlayer2.fake".into())];
        }
        let Some(reply) = self.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames", &()).await else {
            return Vec::new();
        };
        let names: Vec<String> = reply.body().deserialize().unwrap_or_default();
        let mut out: Vec<(String, String)> = Vec::new();
        for bus_name in names.into_iter().filter(|n| n.starts_with(MPRIS)) {
            let short = bus_name[MPRIS.len()..].to_string();
            let ident = match self.call(&bus_name, MPRIS_PATH, PROPS, "Get", &("org.mpris.MediaPlayer2", "Identity")).await {
                Some(r) => r.body().deserialize::<OwnedValue>().map(|v| v_str(&v)).unwrap_or_default(),
                None => short.clone(),
            };
            let mut name = if ident.is_empty() { short } else { ident.clone() };
            let mut n = 2;
            while out.iter().any(|(k, _)| *k == name) {
                name = format!("{ident} {n}");
                n += 1;
            }
            out.push((name, bus_name));
        }
        out
    }

    pub async fn player_state(&self, bus_name: &str) -> Option<Map<String, Value>> {
        if self.fake.is_some() {
            let v = json!({"isPlaying": true, "title": "Song", "artist": "Band", "album": "", "length": 200000, "pos": 1000,
                "volume": 50, "canPause": true, "canPlay": true, "canGoNext": true, "canGoPrevious": true, "canSeek": true});
            return v.as_object().cloned();
        }
        if bus_name.is_empty() {
            return None;
        }
        let reply = self.call(bus_name, MPRIS_PATH, PROPS, "GetAll", &(PLAYER,)).await?;
        let p: HashMap<String, OwnedValue> = reply.body().deserialize().ok()?;
        let get = |k: &str| p.get(k).map(|v| &**v);
        let meta = get("Metadata").map(v_dict).unwrap_or_default();
        let m = |k: &str| meta.get(k).copied();
        let v = json!({
            "isPlaying": get("PlaybackStatus").map(v_str).as_deref() == Some("Playing"),
            "title": m("xesam:title").map(v_str).unwrap_or_default(),
            "artist": m("xesam:artist").map(v_strs).unwrap_or_default().join(", "),
            "album": m("xesam:album").map(v_str).unwrap_or_default(),
            "albumArtUrl": m("mpris:artUrl").map(v_str).unwrap_or_default(),
            "length": m("mpris:length").map_or(0, v_i64) / 1000, "pos": get("Position").map_or(0, v_i64) / 1000,
            "volume": (get("Volume").and_then(v_f64).unwrap_or(1.0) * 100.0) as i64,
            "canPause": get("CanPause").is_some_and(v_bool), "canPlay": get("CanPlay").is_some_and(v_bool),
            "canGoNext": get("CanGoNext").is_some_and(v_bool), "canGoPrevious": get("CanGoPrevious").is_some_and(v_bool),
            "canSeek": get("CanSeek").is_some_and(v_bool),
        });
        v.as_object().cloned()
    }

    pub async fn player_do(&self, bus_name: &str, action: Option<&Value>, volume: Option<&Value>, position: Option<&Value>, seek: Option<&Value>) {
        if self.fake.is_some() {
            let n = |v: Option<&Value>| v.cloned().unwrap_or(Value::Null);
            return self.record("player", json!({"player": bus_name, "action": n(action), "volume": n(volume), "position": n(position), "seek": n(seek)}));
        }
        let action = action.and_then(Value::as_str).unwrap_or("");
        if ["Play", "Pause", "PlayPause", "Stop", "Next", "Previous"].contains(&action) {
            self.call(bus_name, MPRIS_PATH, PLAYER, action, &()).await;
        }
        if let Some(v) = volume.and_then(as_float) {
            self.call(bus_name, MPRIS_PATH, PROPS, "Set", &(PLAYER, "Volume", V::F64(v.clamp(0.0, 100.0) / 100.0))).await;
        }
        if let Some(s) = seek.and_then(as_int) {
            self.call(bus_name, MPRIS_PATH, PLAYER, "Seek", &(s,)).await;
        }
        if let Some(pos) = position.and_then(as_int) {
            let Some(reply) = self.call(bus_name, MPRIS_PATH, PROPS, "Get", &(PLAYER, "Metadata")).await else { return };
            let Ok(meta) = reply.body().deserialize::<OwnedValue>() else { return };
            let track = v_dict(&meta).get("mpris:trackid").map(|v| v_str(v)).unwrap_or_default();
            if let Ok(path) = ObjectPath::try_from(track.as_str()) {
                self.call(bus_name, MPRIS_PATH, PLAYER, "SetPosition", &(path, pos * 1000)).await;
            }
        }
    }

    pub async fn owner(&self, name: &str) -> String {
        match self.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", &(name,)).await {
            Some(r) => r.body().deserialize::<String>().unwrap_or_default(),
            None => String::new(),
        }
    }

    pub async fn watch_players(ctx: Rc<Ctx>) {
        let Some(bus) = ctx.desktop.bus.get().cloned() else { return };
        let Some(mut stream) = signals(&bus, PROPS, "PropertiesChanged", Some(MPRIS_PATH)).await else { return };
        while let Some(Ok(msg)) = stream.next().await {
            let sender = msg.header().sender().map(|s| s.to_string()).unwrap_or_default();
            crate::device::players_changed(&ctx, &sender).await;
        }
    }

    pub async fn pause_for_call(&self) {
        for (_, bus_name) in self.players().await {
            if self.player_state(&bus_name).await.is_some_and(|s| s["isPlaying"] == json!(true)) {
                self.player_do(&bus_name, Some(&json!("Pause")), None, None, None).await;
                self.paused.borrow_mut().push(bus_name);
            }
        }
    }

    pub async fn resume_after_call(&self) {
        let paused = std::mem::take(&mut *self.paused.borrow_mut());
        for bus_name in paused {
            self.player_do(&bus_name, Some(&json!("Play")), None, None, None).await;
        }
    }

    pub fn battery(&self) -> Option<(i64, bool)> {
        if self.fake.is_some() {
            return Some((64, false));
        }
        let base = Path::new("/sys/class/power_supply");
        let mut names: Vec<String> = std::fs::read_dir(base).ok()?.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
        names.sort();
        let d = names.into_iter().find(|d| d.starts_with("BAT"))?;
        let charge = std::fs::read_to_string(base.join(&d).join("capacity")).ok()?.trim().parse().ok()?;
        let status = std::fs::read_to_string(base.join(&d).join("status")).ok()?;
        Some((charge, matches!(status.trim(), "Charging" | "Full")))
    }

    pub fn command(&self, key: &str) {
        if let Some((_, _, cmd)) = COMMANDS.iter().find(|(k, _, _)| *k == key) {
            self.run(cmd);
        }
    }

    pub fn open(&self, target: &str) {
        self.run(&["xdg-open", target]);
    }

    pub async fn downloads(&self) -> PathBuf {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/".into());
        let d = self.output(&["xdg-user-dir", "DOWNLOAD"]).await.trim().to_string();
        let d = if !d.is_empty() && d.trim_end_matches('/') != home.trim_end_matches('/') { PathBuf::from(d) } else { Path::new(&home).join("Downloads") };
        let _ = std::fs::create_dir_all(&d);
        d
    }

    pub fn ring(&self, on: bool) {
        if self.fake.is_some() {
            return self.record("ring", json!({"on": on}));
        }
        if let Some(mut alarm) = self.alarm.borrow_mut().take() {
            let _ = alarm.start_kill();
        }
        if on && let Some(sound) = SOUNDS.iter().find(|s| Path::new(s).exists()) {
            let child = Command::new("sh").args(["-c", "for i in $(seq 30); do pw-play \"$1\" || sleep 1; done", "sh", sound])
                .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
            *self.alarm.borrow_mut() = child.ok();
        }
    }

    pub async fn pick_files(&self, title: &str) -> Vec<String> {
        if self.fake.is_some() {
            return std::env::var("VYNTARIS_PHONE_FAKE_PICK").ok().filter(|p| !p.is_empty()).into_iter().collect();
        }
        let Some(bus) = self.bus.get().cloned() else { return Vec::new() };
        let token = format!("vyntaris_phone_{}_{}", std::process::id(), crate::protocol::now_ms());
        let me = bus.unique_name().map(|n| n.trim_start_matches(':').replace('.', "_")).unwrap_or_default();
        let request = format!("/org/freedesktop/portal/desktop/request/{me}/{token}");
        let Some(mut stream) = signals(&bus, "org.freedesktop.portal.Request", "Response", Some(&request)).await else { return Vec::new() };
        let mut options: HashMap<&str, V> = HashMap::new();
        options.insert("multiple", V::Bool(true));
        options.insert("handle_token", V::from(token.as_str()));
        if self.call(PORTAL, "/org/freedesktop/portal/desktop", "org.freedesktop.portal.FileChooser", "OpenFile", &("", title, options)).await.is_none() {
            return Vec::new();
        }
        let Some(Ok(msg)) = stream.next().await else { return Vec::new() };
        let Ok((response, results)) = msg.body().deserialize::<(u32, HashMap<String, OwnedValue>)>() else { return Vec::new() };
        if response != 0 {
            return Vec::new();
        }
        let uris = results.get("uris").map(|v| v_strs(v)).unwrap_or_default();
        uris.iter().filter_map(|u| u.strip_prefix("file://")).map(|p| unquote(p.find('/').map_or(p, |i| &p[i..]))).collect()
    }
}

fn unquote(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        let hex = |c: u8| (c as char).to_digit(16);
        if b[i] == b'%' && i + 2 < b.len() && let (Some(h), Some(l)) = (hex(b[i + 1]), hex(b[i + 2])) {
            out.push((h * 16 + l) as u8);
            i += 3;
            continue;
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

async fn signals(bus: &zbus::Connection, iface: &str, member: &str, path: Option<&str>) -> Option<zbus::MessageStream> {
    let mut rule = zbus::MatchRule::builder().msg_type(zbus::message::Type::Signal).interface(iface).ok()?.member(member).ok()?;
    if let Some(p) = path {
        rule = rule.path(p).ok()?;
    }
    zbus::MessageStream::for_match_rule(rule.build(), bus, Some(64)).await.ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn special_keys_as_wtype_names_them() {
        assert_eq!(special_key(12).as_deref(), Some("Return"));
        assert_eq!(special_key(1).as_deref(), Some("BackSpace"));
        assert_eq!(special_key(21).as_deref(), Some("F1"));
        assert_eq!(special_key(32).as_deref(), Some("F12"));
        assert_eq!(special_key(33), None);
        assert_eq!(special_key(0), None);
    }

    #[test]
    fn a_uri_path_unquoted() {
        assert_eq!(unquote("/home/a/My%20File.txt"), "/home/a/My File.txt");
        assert_eq!(unquote("/x/%C5%A1.txt"), "/x/š.txt");
        assert_eq!(unquote("/x/100%"), "/x/100%");
    }
}
