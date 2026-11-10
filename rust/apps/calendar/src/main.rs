// Calendar: a week by the hour. A click on an empty hour adds an event there, a click on one changes it. The events,
// their reminders and Google Calendar are the shell's scripts/calendar.py; this is the window onto them.
use adw::prelude::*;
use gtk::{gdk, gio, glib};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use vyntaris_core::i18n::tr;

const HOUR: f64 = 52.0;
const GUTTER: f64 = 56.0;
const STYLE: &str = "
.vyntaris-event { background: @accent_bg_color; color: @accent_fg_color; border-radius: 8px; padding: 4px 6px; box-shadow: none; }
.vyntaris-event:hover { background: shade(@accent_bg_color, 1.06); }
.vyntaris-event label { color: @accent_fg_color; }
.vyntaris-allday { background: @accent_bg_color; color: @accent_fg_color; border-radius: 6px; padding: 1px 6px; min-height: 20px; }
.vyntaris-hour { font-size: 0.8em; font-family: monospace; color: alpha(@window_fg_color, 0.55); }
.vyntaris-today { background: @accent_bg_color; color: @accent_fg_color; border-radius: 99px; min-width: 34px; min-height: 34px; }
";

thread_local! {
    static APP: RefCell<Option<Rc<Cal>>> = const { RefCell::new(None) };
}

fn main() -> glib::ExitCode {
    vyntaris_ui::run_with("org.vyntaris.Calendar", build, |_, call, arg| {
        if let Some(c) = APP.with_borrow(Clone::clone) {
            if call == "open"
                && let Some(d) = day_of(arg)
            {
                c.show(&d);
            }
            c.reload();
        }
    })
}

fn tool() -> String {
    vyntaris_core::paths::shell_dir().join("scripts").join("calendar.py").to_string_lossy().into_owned()
}

async fn run(args: &[&str], input: Option<String>) -> (bool, String) {
    let t = tool();
    let mut argv: Vec<&std::ffi::OsStr> = vec![std::ffi::OsStr::new(&t)];
    argv.extend(args.iter().map(std::ffi::OsStr::new));
    let flags = gio::SubprocessFlags::STDOUT_PIPE | gio::SubprocessFlags::STDERR_SILENCE
        | if input.is_some() { gio::SubprocessFlags::STDIN_PIPE } else { gio::SubprocessFlags::NONE };
    let Ok(p) = gio::Subprocess::newv(&argv, flags) else { return (false, String::new()) };
    let out = p.communicate_utf8_future(input).await.ok().and_then(|(o, _)| o).map(|s| s.to_string());
    (p.is_successful(), out.unwrap_or_default())
}

// Times as the script keeps them: local, "2026-11-12T14:30".
fn day_of(s: &str) -> Option<glib::DateTime> {
    let p: Vec<i32> = s.get(..10)?.split('-').filter_map(|x| x.parse().ok()).collect();
    (p.len() == 3).then(|| glib::DateTime::from_local(p[0], p[1], p[2], 0, 0, 0.0).ok()).flatten()
}
fn hours_of(s: &str) -> f64 {
    let h: f64 = s.get(11..13).and_then(|x| x.parse().ok()).unwrap_or(0.0);
    let m: f64 = s.get(14..16).and_then(|x| x.parse().ok()).unwrap_or(0.0);
    h + m / 60.0
}
fn key(d: &glib::DateTime) -> String {
    format!("{:04}-{:02}-{:02}", d.year(), d.month(), d.day_of_month())
}
fn monday(d: &glib::DateTime) -> glib::DateTime {
    let start = glib::DateTime::from_local(d.year(), d.month(), d.day_of_month(), 0, 0, 0.0).unwrap_or_else(|_| d.clone());
    start.add_days(-(d.day_of_week() - 1)).unwrap_or(start)
}
fn today() -> glib::DateTime {
    glib::DateTime::now_local().map(|n| monday(&n).add_days(n.day_of_week() - 1).unwrap_or(n)).expect("time")
}
fn fmt(d: &glib::DateTime, f: &str) -> String {
    d.format(f).map(|s| s.to_string()).unwrap_or_default()
}

struct Cal {
    win: adw::ApplicationWindow,
    events: RefCell<Vec<Value>>,
    week: RefCell<glib::DateTime>,
    width: Cell<f64>,
    title: gtk::Label,
    heads: Vec<gtk::Label>,
    alldays: Vec<gtk::Box>,
    area: gtk::DrawingArea,
    fixed: gtk::Fixed,
    scroll: gtk::ScrolledWindow,
    month: gtk::Calendar,
    account: gtk::Label,
    connect: gtk::Button,
    sync: gtk::Button,
    google: RefCell<String>,
}

impl Cal {
    fn days(&self) -> Vec<glib::DateTime> {
        let w = self.week.borrow();
        (0..7).filter_map(|i| w.add_days(i).ok()).collect()
    }

    fn on(&self, d: &glib::DateTime) -> Vec<Value> {
        let k = key(d);
        let mut out: Vec<Value> = self.events.borrow().iter().filter(|e| {
            let (s, en) = (e["start"].as_str().unwrap_or(""), e["end"].as_str().unwrap_or(""));
            if e["allDay"].as_bool().unwrap_or(false) { s.get(..10).unwrap_or("") <= k.as_str() && k.as_str() < en.get(..10).unwrap_or("") }
            else { s.get(..10) == Some(k.as_str()) || (s.get(..10).unwrap_or("") < k.as_str() && k.as_str() <= en.get(..10).unwrap_or("") && hours_of(en) > 0.0) }
        }).cloned().collect();
        out.sort_by(|a, b| a["start"].as_str().cmp(&b["start"].as_str()));
        out
    }

    fn show(self: &Rc<Self>, d: &glib::DateTime) {
        *self.week.borrow_mut() = monday(d);
        self.draw();
    }

    fn reload(self: &Rc<Self>) {
        let me = self.clone();
        glib::spawn_future_local(async move {
            let (_, out) = run(&["list"], None).await;
            if let Ok(Value::Array(list)) = serde_json::from_str::<Value>(&out) {
                *me.events.borrow_mut() = list;
            }
            me.draw();
            let (_, st) = run(&["status"], None).await;
            let st: Value = serde_json::from_str(&st).unwrap_or(json!({}));
            *me.google.borrow_mut() = st["google"].as_str().unwrap_or("").to_string();
            me.account_shown(st["client"].as_bool().unwrap_or(false));
        });
    }

    fn sync(self: &Rc<Self>) {
        let me = self.clone();
        self.sync.set_sensitive(false);
        glib::spawn_future_local(async move {
            run(&["sync"], None).await;
            me.sync.set_sensitive(true);
            me.reload();
        });
    }

    fn account_shown(&self, client: bool) {
        let g = self.google.borrow();
        if !g.is_empty() {
            self.account.set_label(&g);
            self.connect.set_label(&tr("Sign out"));
        } else {
            self.account.set_label(&if client { tr("Not connected: events stay on this computer.") } else { tr("Google isn't set up on this computer yet.") });
            self.connect.set_label(&tr("Connect Google"));
        }
        self.connect.set_sensitive(client || !g.is_empty());
        self.sync.set_visible(!g.is_empty());
    }

    fn draw(self: &Rc<Self>) {
        let days = self.days();
        let now = today();
        self.title.set_label(&fmt(&days[3], "%B %Y"));
        for (i, d) in days.iter().enumerate() {
            let is_today = key(d) == key(&now);
            self.heads[i].set_label(&format!("{}\n{}", fmt(d, "%a").to_uppercase(), d.day_of_month()));
            if is_today { self.heads[i].add_css_class("accent") } else { self.heads[i].remove_css_class("accent") }
            let all = &self.alldays[i];
            while let Some(c) = all.first_child() {
                all.remove(&c);
            }
            for e in self.on(d).into_iter().filter(|e| e["allDay"].as_bool().unwrap_or(false)) {
                let b = gtk::Button::builder().css_classes(["vyntaris-allday", "flat"]).build();
                b.set_child(Some(&gtk::Label::builder().label(e["title"].as_str().unwrap_or("")).xalign(0.0)
                    .ellipsize(gtk::pango::EllipsizeMode::End).css_classes(["caption"]).build()));
                let me = self.clone();
                b.connect_clicked(move |_| me.edit(Some(e.clone()), None, None, false));
                all.append(&b);
            }
        }
        self.place();
        self.area.queue_draw();
    }

    // The hours' labels and the timed events, on the grid as wide as it is now.
    fn place(self: &Rc<Self>) {
        let w = self.width.get();
        if w <= GUTTER {
            return;
        }
        while let Some(c) = self.fixed.first_child() {
            self.fixed.remove(&c);
        }
        for h in 1..24 {
            let l = gtk::Label::builder().label(format!("{h:02}:00")).css_classes(["vyntaris-hour"]).width_request(48).xalign(1.0).build();
            self.fixed.put(&l, 0.0, h as f64 * HOUR - 8.0);
        }
        let col = (w - GUTTER) / 7.0;
        for (i, d) in self.days().iter().enumerate() {
            let k = key(d);
            for e in self.on(d).into_iter().filter(|e| !e["allDay"].as_bool().unwrap_or(false)) {
                let (s, en) = (e["start"].as_str().unwrap_or(""), e["end"].as_str().unwrap_or(""));
                let from = if s.get(..10) == Some(k.as_str()) { hours_of(s) } else { 0.0 };
                let to = if en.get(..10) == Some(k.as_str()) { hours_of(en) } else { 24.0 };
                let height = ((to - from) * HOUR - 2.0).max(24.0);
                let inner = gtk::Box::new(gtk::Orientation::Vertical, 0);
                inner.append(&gtk::Label::builder().label(e["title"].as_str().unwrap_or("")).xalign(0.0)
                    .ellipsize(gtk::pango::EllipsizeMode::End).css_classes(["caption-heading"]).build());
                if height > 40.0 {
                    inner.append(&gtk::Label::builder().label(format!("{} – {}", s.get(11..16).unwrap_or(""), en.get(11..16).unwrap_or("")))
                        .xalign(0.0).css_classes(["caption"]).build());
                }
                let b = gtk::Button::builder().child(&inner).css_classes(["vyntaris-event"]).valign(gtk::Align::Start).build();
                b.set_overflow(gtk::Overflow::Hidden);
                b.set_size_request((col - 6.0) as i32, height as i32);
                let me = self.clone();
                b.connect_clicked(move |_| me.edit(Some(e.clone()), None, None, false));
                self.fixed.put(&b, GUTTER + i as f64 * col + 3.0, from * HOUR + 1.0);
            }
        }
    }

    // A new event (on a day, from an hour) or one to change.
    fn edit(self: &Rc<Self>, ev: Option<Value>, day: Option<glib::DateTime>, hour: Option<u32>, all_day: bool) {
        let ev = ev.unwrap_or_else(|| {
            let d = day.unwrap_or_else(today);
            let h = hour.unwrap_or(9).min(23);
            json!({ "title": "", "start": format!("{}T{h:02}:00", key(&d)), "end": format!("{}T{:02}:{}", key(&d), (h + 1).min(23), if h >= 23 { "59" } else { "00" }),
                    "allDay": all_day, "remind": if all_day { 0 } else { 15 } })
        });
        let id = ev["id"].as_str().map(String::from);
        let dialog = adw::Dialog::builder().title(if id.is_some() { tr("Change event") } else { tr("New event") }).content_width(440).build();
        let view = adw::ToolbarView::new();
        view.add_top_bar(&adw::HeaderBar::new());
        let page = gtk::Box::builder().orientation(gtk::Orientation::Vertical).spacing(18).margin_top(6).margin_bottom(24).margin_start(24).margin_end(24).build();
        let group = adw::PreferencesGroup::new();
        let title = adw::EntryRow::builder().title(tr("Title")).text(ev["title"].as_str().unwrap_or("")).build();
        group.add(&title);

        let day = Rc::new(RefCell::new(day_of(ev["start"].as_str().unwrap_or("")).unwrap_or_else(today)));
        let day_row = adw::ActionRow::builder().title(tr("Day")).build();
        let picker = gtk::Calendar::new();
        picker.select_day(&day.borrow());
        let pick = gtk::MenuButton::builder().label(fmt(&day.borrow(), "%A, %e %B %Y")).valign(gtk::Align::Center)
            .popover(&gtk::Popover::builder().child(&picker).build()).build();
        let (dd, pk) = (day.clone(), pick.clone());
        picker.connect_day_selected(move |c| {
            let d = c.date();
            pk.set_label(&fmt(&d, "%A, %e %B %Y"));
            *dd.borrow_mut() = d;
            if let Some(p) = pk.popover() { p.popdown() }
        });
        day_row.add_suffix(&pick);
        group.add(&day_row);

        let all = adw::SwitchRow::builder().title(tr("All day")).active(ev["allDay"].as_bool().unwrap_or(false)).build();
        group.add(&all);
        let start = adw::EntryRow::builder().title(tr("Starts")).text(ev["start"].as_str().and_then(|s| s.get(11..16)).unwrap_or("09:00")).build();
        let end = adw::EntryRow::builder().title(tr("Ends")).text(ev["end"].as_str().and_then(|s| s.get(11..16)).unwrap_or("10:00")).build();
        for r in [&start, &end] {
            all.bind_property("active", r, "visible").invert_boolean().sync_create().build();
            group.add(r);
        }
        let choices = [(-1, tr("None")), (0, tr("At start")), (15, "15 min".to_string()), (60, "1 h".to_string()), (1440, tr("1 day"))];
        let remind = adw::ComboRow::builder().title(tr("Reminder"))
            .model(&gtk::StringList::new(&choices.iter().map(|c| c.1.as_str()).collect::<Vec<_>>())).build();
        let now = ev["remind"].as_i64().unwrap_or(-1);
        remind.set_selected(choices.iter().position(|c| c.0 == now).unwrap_or(0) as u32);
        group.add(&remind);
        page.append(&group);

        let buttons = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        if let Some(id) = id.clone() {
            let del = gtk::Button::builder().label(tr("Delete")).css_classes(["destructive-action", "pill"]).build();
            let (me, dl) = (self.clone(), dialog.clone());
            del.connect_clicked(move |_| {
                let (me, id) = (me.clone(), id.clone());
                dl.close();
                glib::spawn_future_local(async move {
                    run(&["delete", &id], None).await;
                    me.reload();
                });
            });
            buttons.append(&del);
        }
        buttons.append(&gtk::Box::builder().hexpand(true).build());
        let save = gtk::Button::builder().label(tr("Save")).css_classes(["suggested-action", "pill"]).build();
        buttons.append(&save);
        page.append(&buttons);
        view.set_content(Some(&page));
        dialog.set_child(Some(&view));

        let (me, dl, t) = (self.clone(), dialog.clone(), title.clone());
        let done = Rc::new(move || {
            let name = t.text().trim().to_string();
            if name.is_empty() {
                t.add_css_class("error");
                return;
            }
            let ok = |s: String| {
                let p: Vec<u32> = s.trim().split(':').filter_map(|x| x.parse().ok()).collect();
                (p.len() == 2 && p[0] < 24 && p[1] < 60).then(|| format!("{:02}:{:02}", p[0], p[1]))
            };
            let k = key(&day.borrow());
            let s = ok(start.text().to_string()).unwrap_or_else(|| "09:00".into());
            let e = ok(end.text().to_string()).unwrap_or_else(|| s.clone());
            let a = all.is_active();
            let ev = json!({ "title": name, "allDay": a, "remind": choices[remind.selected() as usize].0,
                             "start": format!("{k}T{}", if a { "00:00" } else { &s }), "end": format!("{k}T{}", if a { "00:00" } else { &e }) });
            let (me, id) = (me.clone(), id.clone());
            dl.close();
            glib::spawn_future_local(async move {
                let args: Vec<&str> = match &id { Some(i) => vec!["update", i], None => vec!["add"] };
                run(&args, Some(ev.to_string())).await;
                me.reload();
            });
        });
        let d2 = done.clone();
        save.connect_clicked(move |_| d2());
        let d3 = done.clone();
        title.connect_entry_activated(move |_| d3());
        dialog.present(Some(&self.win));
        title.grab_focus();
    }
}

fn build(app: &adw::Application) -> adw::ApplicationWindow {
    if let Some(display) = gdk::Display::default() {
        let css = gtk::CssProvider::new();
        css.load_from_string(STYLE);
        gtk::style_context_add_provider_for_display(&display, &css, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
    }
    let win = adw::ApplicationWindow::builder().application(app).title(tr("Calendar")).default_width(1100).default_height(760).build();
    vyntaris_ui::escape_closes(&win);

    // The header: new event, today, the weeks before and after.
    let header = adw::HeaderBar::new();
    let title = gtk::Label::builder().css_classes(["title-3"]).build();
    header.set_title_widget(Some(&title));
    let new = gtk::Button::builder().icon_name("list-add-symbolic").label(tr("New event")).css_classes(["suggested-action"]).build();
    new.set_child(Some(&adw::ButtonContent::builder().icon_name("list-add-symbolic").label(tr("New event")).build()));
    let today_b = gtk::Button::with_label(&tr("Today"));
    let prev = gtk::Button::builder().icon_name("go-previous-symbolic").tooltip_text(tr("Previous week")).build();
    let next = gtk::Button::builder().icon_name("go-next-symbolic").tooltip_text(tr("Next week")).build();
    header.pack_start(&new);
    header.pack_end(&next);
    header.pack_end(&prev);
    header.pack_end(&today_b);

    // The side: the month, and the Google account.
    let side = gtk::Box::builder().orientation(gtk::Orientation::Vertical).spacing(12).width_request(280)
        .margin_top(12).margin_bottom(18).margin_start(18).margin_end(12).build();
    let month = gtk::Calendar::new();
    side.append(&month);
    side.append(&gtk::Box::builder().vexpand(true).build());
    side.append(&gtk::Label::builder().label("Google").xalign(0.0).css_classes(["heading"]).build());
    let account = gtk::Label::builder().xalign(0.0).wrap(true).css_classes(["dim-label"]).build();
    side.append(&account);
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let connect = gtk::Button::builder().css_classes(["pill"]).build();
    let sync = gtk::Button::builder().icon_name("view-refresh-symbolic").tooltip_text(tr("Sync now")).css_classes(["circular"]).build();
    row.append(&connect);
    row.append(&sync);
    side.append(&row);

    // The week: day names and all-day events, then the hours.
    let heads_grid = gtk::Grid::builder().column_homogeneous(false).margin_end(12).margin_top(6).margin_bottom(6).build();
    heads_grid.attach(&gtk::Box::builder().width_request(GUTTER as i32).build(), 0, 0, 1, 2);
    let mut heads = vec![];
    let mut alldays = vec![];
    for i in 0..7 {
        let l = gtk::Label::builder().justify(gtk::Justification::Center).hexpand(true).css_classes(["heading"]).build();
        let a = gtk::Box::builder().orientation(gtk::Orientation::Vertical).spacing(2).margin_start(3).margin_end(3).margin_top(4).build();
        heads_grid.attach(&l, i + 1, 0, 1, 1);
        heads_grid.attach(&a, i + 1, 1, 1, 1);
        heads.push(l);
        alldays.push(a);
    }
    let area = gtk::DrawingArea::builder().content_height((24.0 * HOUR) as i32).hexpand(true).css_classes(["accent"]).build();
    let fixed = gtk::Fixed::new();
    let overlay = gtk::Overlay::builder().child(&area).margin_end(12).build();
    overlay.add_overlay(&fixed);
    let scroll = gtk::ScrolledWindow::builder().child(&overlay).vexpand(true).hscrollbar_policy(gtk::PolicyType::Never).build();
    let week_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    week_box.append(&heads_grid);
    week_box.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
    week_box.append(&scroll);

    let body = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    body.append(&side);
    body.append(&gtk::Separator::new(gtk::Orientation::Vertical));
    week_box.set_hexpand(true);
    body.append(&week_box);
    let view = adw::ToolbarView::new();
    view.add_top_bar(&header);
    view.set_content(Some(&body));
    win.set_content(Some(&view));

    let cal = Rc::new(Cal {
        win: win.clone(), events: RefCell::default(), week: RefCell::new(monday(&today())), width: Cell::new(0.0),
        title, heads, alldays, area: area.clone(), fixed, scroll: scroll.clone(), month: month.clone(), account, connect: connect.clone(),
        sync: sync.clone(), google: RefCell::default(),
    });
    APP.set(Some(cal.clone()));

    // The grid: hour lines, day lines, and now.
    let c = cal.clone();
    area.set_draw_func(move |a, cr, w, _| {
        let ink = a.parent().map_or(a.color(), |p| p.color());
        let accent = a.color();
        cr.set_source_rgba(ink.red() as f64, ink.green() as f64, ink.blue() as f64, 0.1);
        cr.set_line_width(1.0);
        let w = w as f64;
        for h in 1..24 {
            cr.move_to(GUTTER, h as f64 * HOUR + 0.5);
            cr.line_to(w, h as f64 * HOUR + 0.5);
        }
        let col = (w - GUTTER) / 7.0;
        for i in 0..7 {
            let x = (GUTTER + i as f64 * col).round() + 0.5;
            cr.move_to(x, 0.0);
            cr.line_to(x, 24.0 * HOUR);
        }
        let _ = cr.stroke();
        if let Ok(n) = glib::DateTime::now_local()
            && let Some(i) = c.days().iter().position(|d| key(d) == key(&n))
        {
            let y = (n.hour() as f64 + n.minute() as f64 / 60.0) * HOUR;
            let x = GUTTER + i as f64 * col;
            cr.set_source_rgba(accent.red() as f64, accent.green() as f64, accent.blue() as f64, 1.0);
            cr.rectangle(x, y - 1.0, col, 2.0);
            let _ = cr.fill();
            cr.arc(x, y, 4.0, 0.0, std::f64::consts::TAU);
            let _ = cr.fill();
        }
    });
    let c = cal.clone();
    area.connect_resize(move |_, w, _| {
        c.width.set(w as f64);
        let c2 = c.clone();
        glib::idle_add_local_once(move || c2.place());
    });

    // An empty hour: a new event there.
    let click = gtk::GestureClick::new();
    let c = cal.clone();
    click.connect_released(move |_, _, x, y| {
        if x < GUTTER {
            return;
        }
        let col = (c.width.get() - GUTTER) / 7.0;
        let i = (((x - GUTTER) / col) as usize).min(6);
        let day = c.days()[i].clone();
        c.edit(None, Some(day), Some((y / HOUR) as u32), false);
    });
    overlay.add_controller(click);

    let c = cal.clone();
    new.connect_clicked(move |_| {
        let n = glib::DateTime::now_local().ok();
        let d = if c.days().iter().any(|d| key(d) == key(&today())) { today() } else { c.week.borrow().clone() };
        c.edit(None, Some(d), Some(n.map_or(9, |n| (n.hour() + 1) as u32)), false);
    });
    let c = cal.clone();
    today_b.connect_clicked(move |_| { c.show(&today()); c.month.select_day(&today()); c.scroll_now(); });
    let c = cal.clone();
    prev.connect_clicked(move |_| { let w = c.week.borrow().add_days(-7).ok(); if let Some(w) = w { c.show(&w); } });
    let c = cal.clone();
    next.connect_clicked(move |_| { let w = c.week.borrow().add_days(7).ok(); if let Some(w) = w { c.show(&w); } });
    let c = cal.clone();
    month.connect_day_selected(move |m| c.show(&m.date()));
    let c = cal.clone();
    sync.connect_clicked(move |_| c.sync());
    let c = cal.clone();
    connect.connect_clicked(move |b| {
        let (c, b) = (c.clone(), b.clone());
        let out = !c.google.borrow().is_empty();
        b.set_sensitive(false);
        glib::spawn_future_local(async move {
            run(&[if out { "disconnect" } else { "connect" }], None).await;
            b.set_sensitive(true);
            c.reload();
        });
    });

    // Ctrl+N: a new event; Page Up and Down: the weeks.
    let keys = gtk::EventControllerKey::new();
    let (n2, p2, x2) = (new.clone(), prev.clone(), next.clone());
    keys.connect_key_pressed(move |_, k, _, m| {
        if m.contains(gdk::ModifierType::CONTROL_MASK) && k == gdk::Key::n { n2.emit_clicked(); return glib::Propagation::Stop; }
        match k {
            gdk::Key::Page_Up => p2.emit_clicked(),
            gdk::Key::Page_Down => x2.emit_clicked(),
            _ => return glib::Propagation::Proceed,
        }
        glib::Propagation::Stop
    });
    win.add_controller(keys);

    // Each minute the now line moves; showing again, the events are read again.
    let a2 = area.clone();
    glib::timeout_add_seconds_local(60, move || { a2.queue_draw(); glib::ControlFlow::Continue });
    let c = cal.clone();
    win.connect_show(move |_| { c.reload(); c.scroll_now(); });

    cal.draw();
    cal.reload();
    cal.sync();
    cal.scroll_now();
    win
}

impl Cal {
    fn scroll_now(&self) {
        let s = self.scroll.clone();
        glib::timeout_add_local_once(std::time::Duration::from_millis(120), move || {
            let h = glib::DateTime::now_local().map_or(8, |n| n.hour()).max(1) - 1;
            s.vadjustment().set_value(h as f64 * HOUR);
        });
    }
}
