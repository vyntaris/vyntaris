use openssl::asn1::Asn1Time;
use openssl::bn::{BigNum, MsbOption};
use openssl::hash::MessageDigest;
use openssl::nid::Nid;
use openssl::pkey::PKey;
use openssl::rsa::Rsa;
use openssl::ssl::{Ssl, SslContext, SslContextBuilder, SslFiletype, SslMethod, SslVerifyMode, SslVersion};
use openssl::x509::extension::{BasicConstraints, SubjectKeyIdentifier};
use openssl::x509::{X509, X509NameBuilder};
use serde_json::{Map, Value, json};
use std::fs;
use std::io::Write;
use std::net::IpAddr;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::LazyLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncBufRead, AsyncBufReadExt, AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{Notify, mpsc};
use tokio::time::timeout;
use tokio_openssl::SslStream;

pub const PROTOCOL: i64 = 8;
pub const MAX_LINE: usize = 4 * 1024 * 1024;
pub const MAX_UNPAIRED: usize = 16;

pub const INCOMING: &[&str] = &["kdeconnect.ping", "kdeconnect.battery", "kdeconnect.clipboard", "kdeconnect.clipboard.connect",
    "kdeconnect.connectivity_report", "kdeconnect.findmyphone.request", "kdeconnect.mousepad.request",
    "kdeconnect.mpris.request", "kdeconnect.notification", "kdeconnect.runcommand.request",
    "kdeconnect.share.request", "kdeconnect.systemvolume.request", "kdeconnect.telephony"];
pub const OUTGOING: &[&str] = &["kdeconnect.ping", "kdeconnect.battery", "kdeconnect.clipboard", "kdeconnect.clipboard.connect",
    "kdeconnect.findmyphone.request", "kdeconnect.mousepad.keyboardstate", "kdeconnect.mpris",
    "kdeconnect.notification.request", "kdeconnect.notification.action", "kdeconnect.runcommand",
    "kdeconnect.share.request", "kdeconnect.systemvolume", "kdeconnect.telephony.request_mute"];

pub struct Config {
    pub udp_port: u16,
    pub peer_udp_port: u16,
    pub tcp_ports: std::ops::Range<u16>,
    pub payload_ports: std::ops::Range<u16>,
    pub testing: bool,
    pub dir: PathBuf,
    pub socket: PathBuf,
}

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

fn port(name: &str, default: u16) -> u16 {
    env(name).and_then(|v| v.parse().ok()).unwrap_or(default)
}

pub static CONFIG: LazyLock<Config> = LazyLock::new(|| {
    let udp_port = port("VYNTARIS_PHONE_UDP_PORT", 1716);
    let (tcp, payload) = (port("VYNTARIS_PHONE_TCP_PORT", 1716), port("VYNTARIS_PHONE_PAYLOAD_PORT", 1739));
    let home = env("HOME").unwrap_or_else(|| "/".into());
    Config {
        udp_port,
        peer_udp_port: port("VYNTARIS_PHONE_PEER_UDP_PORT", udp_port),
        tcp_ports: tcp..tcp.saturating_add(49),
        payload_ports: payload..payload.saturating_add(26),
        testing: env("VYNTARIS_PHONE_TEST").is_some(),
        dir: env("VYNTARIS_PHONE_DIR").map(PathBuf::from).unwrap_or_else(|| {
            PathBuf::from(env("XDG_CONFIG_HOME").unwrap_or_else(|| format!("{home}/.config"))).join("vyntaris/phone")
        }),
        socket: env("VYNTARIS_PHONE_SOCKET").map(PathBuf::from).unwrap_or_else(|| {
            PathBuf::from(env("XDG_RUNTIME_DIR").unwrap_or_else(|| "/tmp".into())).join("vyntaris-phone.sock")
        }),
    }
});

pub fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64)
}

pub fn now_s() -> i64 {
    now_ms() / 1000
}

pub fn valid_id(id: &str) -> bool {
    (32..=38).contains(&id.len()) && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

pub fn packet(kind: &str, body: Value) -> Value {
    json!({"id": now_ms(), "type": kind, "body": if body.is_null() { json!({}) } else { body }})
}

pub fn encode(pkt: &Value) -> Vec<u8> {
    let mut out = serde_json::to_vec(pkt).unwrap_or_default();
    out.push(b'\n');
    out
}

pub fn decode(line: &[u8]) -> Option<Value> {
    let mut pkt: Value = serde_json::from_slice(line).ok()?;
    let obj = pkt.as_object_mut()?;
    obj.get("type")?.as_str()?;
    match obj.get("body") {
        None => {
            obj.insert("body".into(), json!({}));
        }
        Some(b) if !b.is_object() => return None,
        _ => {}
    }
    Some(pkt)
}

pub async fn read_line<R: AsyncBufRead + Unpin>(r: &mut R) -> Option<Vec<u8>> {
    let mut buf = Vec::new();
    let n = (&mut *r).take(MAX_LINE as u64).read_until(b'\n', &mut buf).await.ok()?;
    if n == 0 || (!buf.ends_with(b"\n") && n >= MAX_LINE) {
        return None;
    }
    Some(buf)
}

pub fn pem(der: &[u8]) -> String {
    X509::from_der(der).and_then(|c| c.to_pem()).map(|p| String::from_utf8_lossy(&p).into_owned()).unwrap_or_default()
}

pub fn der_of_pem(pem: &str) -> Option<Vec<u8>> {
    X509::from_pem(pem.as_bytes()).and_then(|c| c.to_der()).ok()
}

pub fn public_key(cert_der: &[u8]) -> Vec<u8> {
    X509::from_der(cert_der).and_then(|c| c.public_key()).and_then(|k| k.public_key_to_der()).unwrap_or_default()
}

pub fn common_name(cert_der: &[u8]) -> String {
    X509::from_der(cert_der)
        .ok()
        .and_then(|c| {
            let cn = c.subject_name().entries_by_nid(Nid::COMMONNAME).next()?.data().to_string().ok()?;
            Some(cn.trim().to_string())
        })
        .unwrap_or_default()
}

pub fn write_atomic(path: &Path, data: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("json.new");
    fs::write(&tmp, data)?;
    fs::rename(tmp, path)
}

pub struct Me {
    pub id: String,
    pub name: String,
    pub kind: String,
    path: PathBuf,
    pub cert: PathBuf,
    pub key: PathBuf,
    pub cert_der: Vec<u8>,
    public: Option<Vec<u8>>,
}

impl Me {
    pub fn load() -> Result<Me, String> {
        let dir = &CONFIG.dir;
        fs::DirBuilder::new().recursive(true).mode(0o700).create(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        let path = dir.join("identity.json");
        let saved: Value = fs::read(&path).ok().and_then(|d| serde_json::from_slice(&d).ok()).unwrap_or_default();
        let saved_id = saved["id"].as_str().unwrap_or("");
        let id = if valid_id(saved_id) { saved_id.to_string() } else { random_hex(16) };
        let name = saved["name"].as_str().filter(|n| !n.is_empty()).map_or_else(default_name, str::to_string);
        let laptop = fs::read_dir("/sys/class/power_supply")
            .map(|d| d.flatten().any(|e| e.file_name().to_string_lossy().starts_with("BAT")))
            .unwrap_or(false);
        let mut me = Me {
            id, name, kind: if laptop { "laptop" } else { "desktop" }.into(), path,
            cert: dir.join("cert.pem"), key: dir.join("key.pem"), cert_der: Vec::new(), public: None,
        };
        if !(me.cert.exists() && me.key.exists()) || saved_id != me.id {
            me.make_certificate().map_err(|e| format!("the certificate: {e}"))?;
        }
        me.save();
        me.cert_der = fs::read_to_string(&me.cert).ok().and_then(|p| der_of_pem(&p)).ok_or("the certificate unreadable")?;
        Ok(me)
    }

    fn make_certificate(&self) -> Result<(), openssl::error::ErrorStack> {
        let key = PKey::from_rsa(Rsa::generate(2048)?)?;
        let mut name = X509NameBuilder::new()?;
        name.append_entry_by_nid(Nid::ORGANIZATIONNAME, "KDE")?;
        name.append_entry_by_nid(Nid::ORGANIZATIONALUNITNAME, "Kde connect")?;
        name.append_entry_by_nid(Nid::COMMONNAME, &self.id)?;
        let name = name.build();
        let mut b = X509::builder()?;
        b.set_version(2)?;
        let mut serial = BigNum::new()?;
        serial.rand(159, MsbOption::MAYBE_ZERO, false)?;
        let serial = serial.to_asn1_integer()?;
        b.set_serial_number(&serial)?;
        b.set_subject_name(&name)?;
        b.set_issuer_name(&name)?;
        b.set_pubkey(&key)?;
        let (from, until) = (Asn1Time::days_from_now(0)?, Asn1Time::days_from_now(3650)?);
        b.set_not_before(&from)?;
        b.set_not_after(&until)?;
        let ski = SubjectKeyIdentifier::new().build(&b.x509v3_context(None, None))?;
        b.append_extension(ski)?;
        b.append_extension(BasicConstraints::new().critical().ca().build()?)?;
        b.sign(&key, MessageDigest::sha256())?;
        let cert = b.build();
        let private = |path: &Path, data: &[u8]| {
            let _ = fs::remove_file(path);
            fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(path).and_then(|mut f| f.write_all(data))
        };
        let ok = private(&self.key, &key.private_key_to_pem_pkcs8()?).and_then(|_| private(&self.cert, &cert.to_pem()?));
        ok.map_err(|_| openssl::error::ErrorStack::get())
    }

    pub fn save(&self) {
        let _ = write_atomic(&self.path, json!({"id": self.id, "name": self.name}).to_string().as_bytes());
    }

    pub fn public(&mut self) -> Vec<u8> {
        if self.public.is_none() {
            self.public = Some(public_key(&self.cert_der));
        }
        self.public.clone().unwrap_or_default()
    }

    pub fn identity(&self, tcp_port: Option<u16>, target: Option<&str>) -> Value {
        let mut body = json!({"deviceId": self.id, "deviceName": self.name, "deviceType": self.kind, "protocolVersion": PROTOCOL,
            "incomingCapabilities": INCOMING, "outgoingCapabilities": OUTGOING});
        if let Some(p) = tcp_port {
            body["tcpPort"] = json!(p);
        }
        if let Some(t) = target {
            body["targetDeviceId"] = json!(t);
            body["targetProtocolVersion"] = json!(PROTOCOL);
        }
        packet("kdeconnect.identity", body)
    }

    fn context(&self, method: SslMethod) -> Result<SslContextBuilder, openssl::error::ErrorStack> {
        let mut b = SslContextBuilder::new(method)?;
        b.set_min_proto_version(Some(SslVersion::TLS1_2))?;
        b.set_certificate_file(&self.cert, SslFiletype::PEM)?;
        b.set_private_key_file(&self.key, SslFiletype::PEM)?;
        Ok(b)
    }

    pub fn client_context(&self) -> Result<SslContext, String> {
        let mut b = self.context(SslMethod::tls_client()).map_err(|e| e.to_string())?;
        b.set_verify(SslVerifyMode::NONE);
        Ok(b.build())
    }

    pub fn server_context(&self, peer_der: &[u8]) -> Result<SslContext, String> {
        let mut b = self.context(SslMethod::tls_server()).map_err(|e| e.to_string())?;
        b.set_verify(SslVerifyMode::PEER | SslVerifyMode::FAIL_IF_NO_PEER_CERT);
        let peer = X509::from_der(peer_der).map_err(|e| e.to_string())?;
        b.cert_store_mut().add_cert(peer).map_err(|e| e.to_string())?;
        Ok(b.build())
    }
}

fn random_hex(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    let _ = openssl::rand::rand_bytes(&mut buf);
    buf.iter().map(|b| format!("{b:02x}")).collect()
}

fn default_name() -> String {
    let pretty = std::process::Command::new("hostnamectl").args(["hostname", "--pretty"]).output().ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
    let host = fs::read_to_string("/proc/sys/kernel/hostname").unwrap_or_default().trim().to_string();
    let name = [pretty, host].into_iter().find(|n| !n.is_empty()).unwrap_or_else(|| "Computer".into());
    name.chars().take(32).collect()
}

pub async fn tls_client(ctx: &SslContext, tcp: TcpStream) -> Result<SslStream<TcpStream>, String> {
    let ssl = Ssl::new(ctx).map_err(|e| e.to_string())?;
    let mut s = SslStream::new(ssl, tcp).map_err(|e| e.to_string())?;
    timeout(Duration::from_secs(10), Pin::new(&mut s).connect()).await.map_err(|_| "TLS timed out")?.map_err(|e| e.to_string())?;
    Ok(s)
}

pub fn peer_cert(s: &SslStream<TcpStream>) -> Option<Vec<u8>> {
    s.ssl().peer_certificate().and_then(|c| c.to_der().ok())
}

pub struct Link {
    pub serial: u64,
    tx: mpsc::UnboundedSender<Vec<u8>>,
    pub address: IpAddr,
    pub cert: Vec<u8>,
    pub closed: Notify,
}

impl Link {
    pub fn new(serial: u64, tx: mpsc::UnboundedSender<Vec<u8>>, address: IpAddr, cert: Vec<u8>) -> Link {
        Link { serial, tx, address, cert, closed: Notify::new() }
    }

    pub fn post(&self, pkt: &Value) {
        let _ = self.tx.send(encode(pkt));
    }

    pub fn close(&self) {
        self.closed.notify_one();
    }
}

fn int(v: &Value) -> Option<i64> {
    v.as_i64().or_else(|| v.as_f64().map(|f| f as i64)).or_else(|| v.as_str().and_then(|s| s.trim().parse().ok()))
}

pub async fn download(ctx: &SslContext, link: &Link, pkt: &Value, dest: &Path) -> Result<(), String> {
    let size = int(&pkt["payloadSize"]).unwrap_or(-1);
    let port = int(&pkt["payloadTransferInfo"]["port"]).unwrap_or(0);
    if !(1..=65535).contains(&port) {
        return Err("no payload".into());
    }
    let connect = async {
        let tcp = TcpStream::connect((link.address, port as u16)).await.map_err(|e| e.to_string())?;
        tls_client(ctx, tcp).await
    };
    let mut s = timeout(Duration::from_secs(15), connect).await.map_err(|_| "the payload timed out")??;
    if peer_cert(&s).as_deref() != Some(&link.cert[..]) {
        return Err("a payload from someone else".into());
    }
    let tmp = PathBuf::from(format!("{}.part", dest.display()));
    let result = async {
        let mut f = tokio::fs::File::create(&tmp).await.map_err(|e| e.to_string())?;
        let mut got: i64 = 0;
        let mut buf = vec![0u8; 1 << 16];
        while size < 0 || got < size {
            let want = if size >= 0 { buf.len().min((size - got) as usize) } else { buf.len() };
            let n = timeout(Duration::from_secs(30), s.read(&mut buf[..want])).await.map_err(|_| "the payload stalled")?.unwrap_or(0);
            if n == 0 {
                break;
            }
            f.write_all(&buf[..n]).await.map_err(|e| e.to_string())?;
            got += n as i64;
        }
        f.flush().await.map_err(|e| e.to_string())?;
        if size >= 0 && got != size {
            return Err("the file came only in part".to_string());
        }
        fs::rename(&tmp, dest).map_err(|e| e.to_string())
    }
    .await;
    let _ = fs::remove_file(&tmp);
    result
}

pub async fn upload(ctx: SslContext, link: &Link, mut pkt: Value, path: &Path) -> Result<(), String> {
    let size = fs::metadata(path).map_err(|e| e.to_string())?.len();
    let mut found = None;
    for port in CONFIG.payload_ports.clone() {
        if let Ok(l) = TcpListener::bind(("0.0.0.0", port)).await {
            found = Some((l, port));
            break;
        }
    }
    let (listener, port) = found.ok_or("no port free to send from")?;
    pkt["payloadSize"] = json!(size);
    pkt["payloadTransferInfo"] = json!({"port": port});
    link.post(&pkt);
    let give = async {
        loop {
            let Ok((tcp, _)) = listener.accept().await else { continue };
            let Ok(ssl) = Ssl::new(&ctx) else { continue };
            let Ok(mut s) = SslStream::new(ssl, tcp) else { continue };
            if timeout(Duration::from_secs(10), Pin::new(&mut s).accept()).await.ok().and_then(Result::ok).is_none() {
                continue;
            }
            let mut f = tokio::fs::File::open(path).await.map_err(|e| e.to_string())?;
            tokio::io::copy(&mut f, &mut s).await.map_err(|e| e.to_string())?;
            let _ = s.shutdown().await;
            return Ok::<(), String>(());
        }
    };
    timeout(Duration::from_secs(120), give).await.map_err(|_| "the phone didn't take the file".to_string())?
}

pub fn truthy(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64() != Some(0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

pub fn as_int(v: &Value) -> Option<i64> {
    match v {
        Value::Bool(b) => Some(*b as i64),
        _ => int(v),
    }
}

pub fn as_float(v: &Value) -> Option<f64> {
    v.as_f64().or_else(|| v.as_str().and_then(|s| s.trim().parse().ok())).or_else(|| v.as_bool().map(|b| b as i64 as f64))
}

pub fn text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Null => "None".into(),
        other => other.to_string(),
    }
}

pub fn first_text(body: &Map<String, Value>, keys: &[&str], fallback: &str) -> String {
    keys.iter().filter_map(|k| body.get(*k)).find(|v| truthy(v)).map_or_else(|| fallback.to_string(), text)
}
