use adw::prelude::*;
use gtk::{gdk, gio, glib};
use std::cell::RefCell;
use std::rc::Rc;

const STYLE: &str = include_str!("style.css");

pub fn run(id: &str, build: impl Fn(&adw::Application) -> adw::ApplicationWindow + 'static) -> glib::ExitCode {
    run_with(id, build, |_, _, _| {})
}

pub fn run_with(
    id: &str,
    build: impl Fn(&adw::Application) -> adw::ApplicationWindow + 'static,
    called: impl Fn(&adw::ApplicationWindow, &str, &str) + 'static,
) -> glib::ExitCode {
    if std::env::var_os("GSK_RENDERER").is_none() {
        unsafe { std::env::set_var("GSK_RENDERER", "cairo") };
    }
    let app = adw::Application::builder().application_id(id).flags(gio::ApplicationFlags::HANDLES_COMMAND_LINE).build();
    let window: Rc<RefCell<Option<adw::ApplicationWindow>>> = Rc::default();
    app.connect_startup(|_| theme());
    let w = window.clone();
    app.connect_command_line(move |app, cmd| {
        let args: Vec<String> = cmd.arguments().iter().skip(1).map(|a| a.to_string_lossy().into_owned()).collect();
        let call = args.first().map_or("open", String::as_str);
        let arg = args.get(1).map_or("", String::as_str);
        let mut slot = w.borrow_mut();
        let win = match slot.as_ref() {
            Some(win) if call == "close" || (call == "toggle" && win.is_visible() && win.is_active()) => {
                win.close();
                return 0.into();
            }
            None if call == "close" => return 0.into(),
            Some(win) => win.clone(),
            None => {
                let win = build(app);
                win.set_hide_on_close(true);
                linger(&w, &win);
                *slot = Some(win.clone());
                win
            }
        };
        drop(slot);
        win.present();
        called(&win, if call == "toggle" { "open" } else { call }, arg);
        0.into()
    });
    app.run()
}

pub fn run_each(id: &str, build: impl Fn(&adw::Application) -> adw::ApplicationWindow + 'static) -> glib::ExitCode {
    if std::env::var_os("GSK_RENDERER").is_none() {
        unsafe { std::env::set_var("GSK_RENDERER", "cairo") };
    }
    let app = adw::Application::builder().application_id(id).flags(gio::ApplicationFlags::NON_UNIQUE).build();
    app.connect_startup(|_| theme());
    app.connect_activate(move |app| build(app).present());
    app.run_with_args::<&str>(&[])
}

fn linger(slot: &Rc<RefCell<Option<adw::ApplicationWindow>>>, win: &adw::ApplicationWindow) {
    let timer: Rc<RefCell<Option<glib::SourceId>>> = Rc::default();
    let (t, s) = (timer.clone(), slot.clone());
    win.connect_hide(move |_| {
        let (t2, s2) = (t.clone(), s.clone());
        let id = glib::timeout_add_seconds_local_once(120, move || {
            t2.borrow_mut().take();
            if let Some(w) = s2.borrow_mut().take() {
                w.destroy();
            }
        });
        if let Some(old) = t.borrow_mut().replace(id) {
            old.remove();
        }
    });
    win.connect_show(move |_| {
        if let Some(id) = timer.borrow_mut().take() {
            id.remove();
        }
    });
}

fn theme() {
    let Some(display) = gdk::Display::default() else { return };
    let look = gtk::CssProvider::new();
    look.load_from_string(STYLE);
    gtk::style_context_add_provider_for_display(&display, &look, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);

    let colours = gtk::CssProvider::new();
    let file = gio::File::for_path(vyntaris_core::paths::config_home().join("gtk-4.0").join("gtk.css"));
    colours.load_from_file(&file);
    gtk::style_context_add_provider_for_display(&display, &colours, gtk::STYLE_PROVIDER_PRIORITY_USER + 1);
    if let Ok(monitor) = file.monitor_file(gio::FileMonitorFlags::NONE, gio::Cancellable::NONE) {
        monitor.connect_changed(move |_, f, _, event| {
            if matches!(event, gio::FileMonitorEvent::ChangesDoneHint | gio::FileMonitorEvent::Created) {
                colours.load_from_file(f);
            }
        });
        std::mem::forget(monitor);
    }
}

pub fn keycap(text: &str) -> gtk::Label {
    let l = gtk::Label::new(Some(text));
    l.add_css_class("keycap");
    l.add_css_class("vyntaris-key");
    l
}

pub fn shell(target: &str, function: &str, args: &[&str]) {
    let mut cmd = vec!["qs", "-c", "vyntaris", "ipc", "call", target, function];
    cmd.extend_from_slice(args);
    let _ = gio::Subprocess::newv(&cmd.iter().map(std::ffi::OsStr::new).collect::<Vec<_>>(), gio::SubprocessFlags::STDOUT_SILENCE | gio::SubprocessFlags::STDERR_SILENCE);
}

pub fn launch(command: &[&str]) {
    let mut cmd = vec!["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app.slice", "--"];
    cmd.extend_from_slice(command);
    let _ = gio::Subprocess::newv(&cmd.iter().map(std::ffi::OsStr::new).collect::<Vec<_>>(), gio::SubprocessFlags::NONE);
}

pub fn in_terminal(script: &str) {
    let terminal = vyntaris_core::settings::Settings::load().str("apps.terminalRun", "kitty");
    launch(&["sh", "-c", &format!("{terminal} sh -c \"$1\""), "sh", script]);
}

pub fn escape_closes(win: &(impl IsA<gtk::Window> + IsA<gtk::Widget>)) {
    let keys = gtk::ShortcutController::new();
    keys.add_shortcut(gtk::Shortcut::new(
        gtk::ShortcutTrigger::parse_string("Escape"),
        Some(gtk::CallbackAction::new(|w, _| {
            if let Some(w) = w.downcast_ref::<gtk::Window>() {
                w.close();
            }
            glib::Propagation::Stop
        })),
    ));
    win.add_controller(keys);
}

#[derive(Clone)]
pub struct Segments {
    area: gtk::DrawingArea,
    fraction: Rc<std::cell::Cell<f64>>,
    tick: Rc<RefCell<Option<gtk::TickCallbackId>>>,
}

impl Default for Segments {
    fn default() -> Self {
        Self::new()
    }
}

impl Segments {
    pub fn new() -> Self {
        let area = gtk::DrawingArea::builder().content_height(14).hexpand(true).valign(gtk::Align::Center).css_classes(["accent"]).build();
        let fraction = Rc::new(std::cell::Cell::new(0.0f64));
        let f = fraction.clone();
        area.set_draw_func(move |a, cr, w, h| {
            let (gap, w, h) = (3.0, w as f64, h as f64);
            let count = ((w + gap) / 9.0).round().max(8.0) as i32;
            let cell = (w - gap * (count - 1) as f64) / count as f64;
            let accent = a.color();
            let ink = a.parent().map_or(accent, |p| p.color());
            let bright = gdk::RGBA::new(
                accent.red() + (1.0 - accent.red()) * 0.3, accent.green() + (1.0 - accent.green()) * 0.3,
                accent.blue() + (1.0 - accent.blue()) * 0.3, accent.alpha());
            let p = f.get();
            let (from, to) = if p >= 0.0 {
                (0, (p.clamp(0.0, 1.0) * count as f64).round() as i32)
            } else {
                let at = ((a.frame_clock().map_or(0, |c| c.frame_time()) as f64 / 70_000.0) as i32) % (count + 4) - 4;
                (at, at + 4)
            };
            for i in 0..count {
                let on = i >= from && i < to;
                let ch = if on { 12.0f64.min(h) } else { 6.0f64.min(h) };
                let (x, y) = (i as f64 * (cell + gap), (h - ch) / 2.0);
                let c = if !on { gdk::RGBA::new(ink.red(), ink.green(), ink.blue(), 0.12) } else if i == to - 1 && p >= 0.0 { bright } else { accent };
                cr.set_source_rgba(c.red() as f64, c.green() as f64, c.blue() as f64, c.alpha() as f64);
                let r = 2.0f64.min(cell / 2.0);
                cr.new_sub_path();
                cr.arc(x + cell - r, y + r, r, -std::f64::consts::FRAC_PI_2, 0.0);
                cr.arc(x + cell - r, y + ch - r, r, 0.0, std::f64::consts::FRAC_PI_2);
                cr.arc(x + r, y + ch - r, r, std::f64::consts::FRAC_PI_2, std::f64::consts::PI);
                cr.arc(x + r, y + r, r, std::f64::consts::PI, 1.5 * std::f64::consts::PI);
                cr.close_path();
                let _ = cr.fill();
            }
        });
        Segments { area, fraction, tick: Rc::default() }
    }

    pub fn widget(&self) -> &gtk::DrawingArea {
        &self.area
    }

    pub fn set_fraction(&self, f: f64) {
        if let Some(id) = self.tick.borrow_mut().take() {
            id.remove();
        }
        self.fraction.set(f.clamp(0.0, 1.0));
        self.area.queue_draw();
    }

    pub fn pulse(&self) {
        self.fraction.set(-1.0);
        if self.tick.borrow().is_none() {
            let id = self.area.add_tick_callback(|a, _| {
                a.queue_draw();
                glib::ControlFlow::Continue
            });
            self.tick.replace(Some(id));
        }
    }
}

pub fn which(name: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(name).is_file()))
}
