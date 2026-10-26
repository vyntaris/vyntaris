use gio::prelude::*;
use glib::{Variant, VariantDict};
use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

const OBEX: &str = "org.bluez.obex";

fn notify(title: &str, body: &str) {
    let _ = std::process::Command::new("notify-send").args(["-a", "Bluetooth", "-i", "bluetooth", title, body]).status();
}

fn names(files: &[PathBuf]) -> String {
    files.iter().filter_map(|f| f.file_name()).map(|f| f.to_string_lossy().to_string()).collect::<Vec<_>>().join(", ")
}

fn connected_device(system: &gio::DBusConnection) -> Option<(String, String)> {
    let objects = system
        .call_sync(Some("org.bluez"), "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None, None,
            gio::DBusCallFlags::NONE, -1, gio::Cancellable::NONE)
        .ok()?
        .try_child_value(0)?;
    for entry in objects.iter() {
        let ifaces = entry.try_child_value(1)?;
        let Some(dev) = ifaces.iter().find(|e| e.child_value(0).str() == Some("org.bluez.Device1")).map(|e| e.child_value(1)) else { continue };
        let dev = VariantDict::new(Some(&dev));
        if dev.lookup_value("Connected", None).and_then(|v| v.get::<bool>()) == Some(true) {
            let address = dev.lookup_value("Address", None).and_then(|v| v.get::<String>())?;
            let alias = dev.lookup_value("Alias", None).and_then(|v| v.get::<String>()).unwrap_or_else(|| address.clone());
            return Some((address, alias));
        }
    }
    None
}

fn call(bus: &gio::DBusConnection, path: &str, iface: &str, method: &str, args: Variant) -> Result<Variant, glib::Error> {
    bus.call_sync(Some(OBEX), path, iface, method, Some(&args), None, gio::DBusCallFlags::NONE, -1, gio::Cancellable::NONE)
}

fn main() {
    let files: Vec<PathBuf> = std::env::args().skip(1).map(PathBuf::from).filter(|f| f.is_file()).collect();
    if files.is_empty() {
        return;
    }
    let session = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE).expect("the session bus");
    let system = gio::bus_get_sync(gio::BusType::System, gio::Cancellable::NONE).expect("the system bus");
    let Some((address, name)) = connected_device(&system) else {
        notify("Nothing to send to", "Connect a phone or computer over Bluetooth first.");
        std::process::exit(1);
    };
    let target = VariantDict::new(None);
    target.insert("Target", "opp");
    let session_path = match call(&session, "/org/bluez/obex", "org.bluez.obex.Client1", "CreateSession", (address, target.end()).to_variant()) {
        Ok(v) => v.child_value(0),
        Err(e) => {
            notify(&format!("Can't reach {name}"), e.message().rsplit(':').next().unwrap_or("").trim());
            std::process::exit(1);
        }
    };
    let session_str = session_path.str().unwrap_or_default().to_string();

    notify(&format!("Sending to {name}"), &names(&files));
    let main = glib::MainLoop::new(None, false);
    let state = Rc::new(RefCell::new((files, Vec::<PathBuf>::new(), Vec::<PathBuf>::new())));
    send_next(&session, &session_str, state.clone(), main.clone());
    main.run();
    let _ = call(&session, "/org/bluez/obex", "org.bluez.obex.Client1", "RemoveSession", (session_path,).to_variant());

    let (_, sent, failed) = &*state.borrow();
    if failed.is_empty() {
        notify(&format!("Sent to {name}"), &names(sent));
    } else {
        notify(&format!("Not sent to {name}"), &names(failed));
    }
}

type State = Rc<RefCell<(Vec<PathBuf>, Vec<PathBuf>, Vec<PathBuf>)>>;

fn send_next(bus: &gio::DBusConnection, session: &str, state: State, main: glib::MainLoop) {
    let Some(path) = ({ let mut s = state.borrow_mut(); if s.0.is_empty() { None } else { Some(s.0.remove(0)) } }) else {
        main.quit();
        return;
    };
    let abs = std::fs::canonicalize(&path).unwrap_or_else(|_| path.clone());
    let transfer = match call(bus, session, "org.bluez.obex.ObjectPush1", "SendFile", (abs.to_string_lossy().to_string(),).to_variant()) {
        Ok(v) => v.child_value(0).str().unwrap_or_default().to_string(),
        Err(_) => {
            state.borrow_mut().2.push(path);
            return send_next(bus, session, state, main);
        }
    };
    let sub: Rc<RefCell<Option<gio::SignalSubscriptionId>>> = Rc::default();
    let (s, b, sess) = (sub.clone(), bus.clone(), session.to_string());
    #[allow(deprecated)]
    let id = bus.signal_subscribe(Some(OBEX), Some("org.freedesktop.DBus.Properties"), Some("PropertiesChanged"), Some(&transfer),
        None, gio::DBusSignalFlags::NONE, move |conn, _, _, _, _, params| {
            let status = params.try_child_value(1).map(|d| VariantDict::new(Some(&d)))
                .and_then(|d| d.lookup_value("Status", None)).and_then(|v| v.get::<String>()).unwrap_or_default();
            if status != "complete" && status != "error" {
                return;
            }
            if let Some(id) = s.borrow_mut().take() {
                #[allow(deprecated)]
                conn.signal_unsubscribe(id);
            }
            {
                let mut st = state.borrow_mut();
                if status == "complete" { st.1.push(path.clone()) } else { st.2.push(path.clone()) }
            }
            send_next(&b, &sess, state.clone(), main.clone());
        });
    *sub.borrow_mut() = Some(id);
}
