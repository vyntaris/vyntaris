use gio::prelude::*;
use glib::VariantDict;
use std::cell::RefCell;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;

const OBEX: &str = "org.bluez.obex";
const AGENT_PATH: &str = "/org/vyntaris/obex/agent";
const AGENT_XML: &str = r#"
<node>
  <interface name="org.bluez.obex.Agent1">
    <method name="Release"/>
    <method name="AuthorizePush">
      <arg type="o" name="transfer" direction="in"/>
      <arg type="s" name="filename" direction="out"/>
    </method>
    <method name="Cancel"/>
  </interface>
</node>"#;

struct Agent {
    session: gio::DBusConnection,
    system: Option<gio::DBusConnection>,
    pending: RefCell<HashMap<String, (gio::DBusMethodInvocation, gio::Subprocess)>>,
    target: PathBuf,
    incoming: PathBuf,
}

fn props(bus: &gio::DBusConnection, name: &str, path: &str, iface: &str) -> VariantDict {
    bus.call_sync(Some(name), path, "org.freedesktop.DBus.Properties", "GetAll", Some(&(iface,).to_variant()),
        None, gio::DBusCallFlags::NONE, -1, gio::Cancellable::NONE)
        .ok()
        .and_then(|v| v.try_child_value(0))
        .map(|d| VariantDict::new(Some(&d)))
        .unwrap_or_else(|| VariantDict::new(None))
}

fn text(d: &VariantDict, key: &str) -> Option<String> {
    d.lookup_value(key, None).and_then(|v| v.str().map(str::to_string))
}

pub fn size_text(n: u64) -> String {
    let mut n = n as f64;
    for unit in ["B", "KB", "MB", "GB"] {
        if n < 1000.0 || unit == "GB" {
            return if unit == "B" { format!("{n:.0} {unit}") } else { format!("{n:.1} {unit}") };
        }
        n /= 1000.0;
    }
    unreachable!()
}

pub fn free_name(dir: &Path, name: &str) -> PathBuf {
    let file = Path::new(name).file_name().and_then(|f| f.to_str()).filter(|f| !f.is_empty()).unwrap_or("file");
    let (base, ext) = match file.rfind('.') {
        Some(i) if i > 0 => (&file[..i], &file[i..]),
        _ => (file, ""),
    };
    let mut path = dir.join(file);
    let mut i = 1;
    while path.exists() {
        path = dir.join(format!("{base} ({i}){ext}"));
        i += 1;
    }
    path
}

fn notify(args: &[&str], answered: Option<Box<dyn FnOnce(String)>>) -> Option<gio::Subprocess> {
    let mut argv: Vec<&std::ffi::OsStr> = ["notify-send", "-a", "Bluetooth", "-i", "bluetooth"].iter().map(|s| s.as_ref()).collect();
    argv.extend(args.iter().map(std::ffi::OsStr::new));
    let proc = gio::Subprocess::newv(&argv, gio::SubprocessFlags::STDOUT_PIPE).ok()?;
    if let Some(done) = answered {
        proc.communicate_utf8_async(None, gio::Cancellable::NONE, move |res| {
            let out = res.ok().and_then(|(o, _)| o).map(|s| s.trim().to_string()).unwrap_or_default();
            done(out);
        });
    }
    Some(proc)
}

impl Agent {
    fn sender_name(&self, transfer: &str) -> String {
        let session_path = text(&props(&self.session, OBEX, transfer, "org.bluez.obex.Transfer1"), "Session").unwrap_or_default();
        let address = text(&props(&self.session, OBEX, &session_path, "org.bluez.obex.Session1"), "Destination").unwrap_or_default();
        if let Some(system) = &self.system {
            for adapter in ["hci0", "hci1"] {
                let dev = props(system, "org.bluez", &format!("/org/bluez/{adapter}/dev_{}", address.replace(':', "_")), "org.bluez.Device1");
                if let Some(alias) = text(&dev, "Alias") {
                    return alias;
                }
            }
        }
        if address.is_empty() { "A device".into() } else { address }
    }

    fn authorize(self: &Rc<Self>, transfer: String, invocation: gio::DBusMethodInvocation) {
        let info = props(&self.session, OBEX, &transfer, "org.bluez.obex.Transfer1");
        let name = text(&info, "Name").unwrap_or_else(|| "file".into());
        let size = info.lookup_value("Size", None).and_then(|v| v.get::<u64>()).unwrap_or(0);
        let me = self.clone();
        let (t, n) = (transfer.clone(), name.clone());
        let proc = notify(
            &["-u", "critical", "-A", "accept=Accept", "-A", "decline=Decline",
              &format!("{} wants to send a file", self.sender_name(&transfer)), &format!("{name} · {}", size_text(size))],
            Some(Box::new(move |choice| me.answered(&t, &n, &choice))),
        );
        match proc {
            Some(p) => {
                self.pending.borrow_mut().insert(transfer, (invocation, p));
            }
            None => invocation.return_dbus_error("org.bluez.obex.Error.Rejected", "Couldn't ask"),
        }
    }

    fn answered(self: &Rc<Self>, transfer: &str, name: &str, choice: &str) {
        let Some((invocation, _)) = self.pending.borrow_mut().remove(transfer) else { return };
        if choice != "accept" {
            invocation.return_dbus_error("org.bluez.obex.Error.Rejected", "Declined");
            return;
        }
        let _ = std::fs::create_dir_all(&self.incoming);
        let part = self.incoming.join(format!("incoming-{}", transfer.trim_matches('/').replace('/', "-")));
        self.watch(transfer, part.clone(), name.to_string());
        invocation.return_value(Some(&(part.to_string_lossy().to_string(),).to_variant()));
    }

    fn watch(self: &Rc<Self>, transfer: &str, part: PathBuf, name: String) {
        let me = self.clone();
        let sub: Rc<RefCell<Option<gio::SignalSubscriptionId>>> = Rc::default();
        let s = sub.clone();
        #[allow(deprecated)]
        let id = self.session.signal_subscribe(Some(OBEX), Some("org.freedesktop.DBus.Properties"), Some("PropertiesChanged"),
            Some(transfer), None, gio::DBusSignalFlags::NONE, move |conn, _, _, _, _, params| {
                let changed = params.try_child_value(1).map(|d| VariantDict::new(Some(&d)));
                let status = changed.as_ref().and_then(|d| text(d, "Status")).unwrap_or_default();
                if status != "complete" && status != "error" {
                    return;
                }
                if let Some(id) = s.borrow_mut().take() {
                    #[allow(deprecated)]
                    conn.signal_unsubscribe(id);
                }
                if status == "error" {
                    let _ = std::fs::remove_file(&part);
                    notify(&["Didn't arrive", &name], None);
                    return;
                }
                let _ = std::fs::create_dir_all(&me.target);
                let path = free_name(&me.target, &name);
                let shown = path.file_name().map(|f| f.to_string_lossy().to_string()).unwrap_or_default();
                if std::fs::rename(&part, &path).is_err()
                    && std::fs::copy(&part, &path).map(|_| std::fs::remove_file(&part)).is_err()
                {
                    notify(&["Couldn't save", &shown], None);
                    return;
                }
                notify(&["-A", "open=Open", "Received", &shown], Some(Box::new(move |c| {
                    if c == "open" {
                        let _ = gio::Subprocess::newv(&["xdg-open".as_ref(), path.as_os_str()], gio::SubprocessFlags::NONE);
                    }
                })));
            });
        *sub.borrow_mut() = Some(id);
    }

    fn cancel(&self) {
        for (_, (invocation, proc)) in self.pending.borrow_mut().drain() {
            proc.force_exit();
            invocation.return_dbus_error("org.bluez.obex.Error.Canceled", "Canceled");
        }
    }

    fn register(&self) {
        let _ = self.session.call_sync(Some(OBEX), "/org/bluez/obex", "org.bluez.obex.AgentManager1", "RegisterAgent",
            Some(&(glib::variant::ObjectPath::try_from(AGENT_PATH).expect("a path"),).to_variant()),
            None, gio::DBusCallFlags::NONE, -1, gio::Cancellable::NONE);
    }
}

fn main() {
    let session = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE).expect("the session bus");
    let system = gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE).ok();
    let downloads = glib::user_special_dir(glib::UserDirectory::Downloads).unwrap_or_else(|| glib::home_dir().join("Downloads"));
    let agent = Rc::new(Agent {
        session: session.clone(),
        system,
        pending: RefCell::default(),
        target: downloads.join("Bluetooth"),
        incoming: glib::user_cache_dir().join("obexd"),
    });

    let node = gio::DBusNodeInfo::for_xml(AGENT_XML).expect("the agent's interface");
    let iface = node.lookup_interface("org.bluez.obex.Agent1").expect("Agent1");
    let a = agent.clone();
    let _registration = session
        .register_object(AGENT_PATH, &iface)
        .method_call(move |_, _, _, _, method, params, invocation| match method {
            "AuthorizePush" => {
                let transfer = params.try_child_value(0).and_then(|v| v.str().map(str::to_string)).unwrap_or_default();
                a.authorize(transfer, invocation);
            }
            "Cancel" => {
                a.cancel();
                invocation.return_value(None);
            }
            _ => invocation.return_value(None),
        })
        .build()
        .expect("the agent registered on the bus");

    let a = agent.clone();
    let _watch = gio::bus_watch_name_on_connection(&session, OBEX, gio::BusNameWatcherFlags::AUTO_START,
        move |_, _, _| a.register(), |_, _| {});
    glib::MainLoop::new(None, false).run();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_said_as_people_say_them() {
        assert_eq!(size_text(512), "512 B");
        assert_eq!(size_text(2_500_000), "2.5 MB");
        assert_eq!(size_text(7_000_000_000_000), "7000.0 GB");
    }

    #[test]
    fn a_name_no_file_has() {
        let dir = std::env::temp_dir().join(format!("obex-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        assert_eq!(free_name(&dir, "photo.jpg"), dir.join("photo.jpg"));
        std::fs::write(dir.join("photo.jpg"), "").unwrap();
        assert_eq!(free_name(&dir, "photo.jpg"), dir.join("photo (1).jpg"));
        assert_eq!(free_name(&dir, "../../etc/passwd"), dir.join("passwd"));
        assert_eq!(free_name(&dir, ""), dir.join("file"));
        std::fs::remove_dir_all(dir).unwrap();
    }
}
