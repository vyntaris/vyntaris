use vyntaris_core::i18n::tr;
use adw::prelude::*;
use gtk::{gdk, gio, glib};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

fn main() -> glib::ExitCode {
    vyntaris_ui::run_each("org.vyntaris.SharePicker", build)
}

struct Window {
    id: String,
    app: String,
    title: String,
}

fn windows(list: &str) -> Vec<Window> {
    let sep = if list.contains("[HA>]") {
        "[HA>]"
    } else {
        "[HE>]"
    };
    list.split(sep)
        .filter_map(|e| {
            let (id, rest) = e.split_once("[HC>]")?;
            let (app, rest) = rest.split_once("[HT>]")?;
            let title = rest.split("[HE>]").next().unwrap_or("");
            Some(Window {
                id: id.into(),
                app: app.into(),
                title: title.into(),
            })
        })
        .collect()
}

fn screen_title(name: &str, model: &str) -> String {
    if ["eDP", "LVDS", "DSI"].iter().any(|p| name.starts_with(p)) {
        return tr("Built-in screen").into();
    }
    let code = model
        .trim_start_matches("0x")
        .chars()
        .all(|c| c.is_ascii_hexdigit());
    if !model.is_empty() && !code {
        model.into()
    } else {
        name.into()
    }
}

fn app_of(app_id: &str) -> (String, Option<gio::Icon>) {
    let want = app_id.to_lowercase();
    let found = gio::AppInfo::all().into_iter().find(|i| {
        let id = i
            .id()
            .map(|s| s.trim_end_matches(".desktop").to_lowercase())
            .unwrap_or_default();
        id == want || id.rsplit('.').next() == Some(want.as_str())
    });
    match found {
        Some(i) => (i.display_name().to_string(), i.icon()),
        None => (app_id.to_string(), None),
    }
}

struct Picker {
    picked: RefCell<String>,
    answered: Cell<bool>,
    remember: adw::SwitchRow,
    win: RefCell<Option<adw::ApplicationWindow>>,
}

impl Picker {
    fn answer(&self, selection: &str) {
        if self.answered.replace(true) {
            return;
        }
        if !selection.is_empty() {
            println!(
                "[SELECTION]{}/{selection}",
                if self.remember.is_active() { "r" } else { "" }
            );
        }
        if let Some(w) = self.win.borrow_mut().take() {
            w.destroy();
        }
    }

    fn region(self: &Rc<Self>) {
        let Some(win) = self.win.borrow().clone() else {
            return;
        };
        win.set_visible(false);
        let p = self.clone();
        glib::spawn_future_local(async move {
            let got = match gio::Subprocess::newv(
                &[
                    "slurp".as_ref(),
                    "-b".as_ref(),
                    "#00000080".as_ref(),
                    "-s".as_ref(),
                    "#00000000".as_ref(),
                    "-f".as_ref(),
                    "%o@%x,%y,%w,%h".as_ref(),
                ],
                gio::SubprocessFlags::STDOUT_PIPE,
            ) {
                Ok(s) => s
                    .communicate_utf8_future(None)
                    .await
                    .ok()
                    .and_then(|(o, _)| o)
                    .map(|o| o.trim().to_string())
                    .unwrap_or_default(),
                Err(_) => String::new(),
            };
            let shape = regex::Regex::new(r"^\S+@-?\d+,-?\d+,\d+,\d+$").unwrap();
            if shape.is_match(&got) {
                p.answer(&format!("region:{got}"));
            } else {
                win.set_visible(true);
            }
        });
    }
}

fn row(
    title: &str,
    subtitle: &str,
    icon: Option<gio::Icon>,
    fallback: &str,
    value: &str,
) -> gtk::ListBoxRow {
    let r = adw::ActionRow::builder()
        .title(glib::markup_escape_text(title))
        .subtitle(glib::markup_escape_text(subtitle))
        .activatable(true)
        .name(value)
        .build();
    let image = match icon {
        Some(i) => gtk::Image::from_gicon(&i),
        None => gtk::Image::from_icon_name(fallback),
    };
    image.set_pixel_size(28);
    r.add_prefix(&image);
    r.upcast()
}

fn build(app: &adw::Application) -> adw::ApplicationWindow {
    let p = Rc::new(Picker {
        picked: RefCell::default(),
        answered: Cell::new(false),
        remember: adw::SwitchRow::builder()
            .title(tr("Let this app share it again without asking"))
            .build(),
        win: RefCell::default(),
    });

    let list = gtk::ListBox::builder()
        .css_classes(["boxed-list"])
        .activate_on_single_click(false)
        .valign(gtk::Align::Start)
        .build();
    let tabs = adw::ToggleGroup::new();
    tabs.add(
        adw::Toggle::builder()
            .name("screens")
            .label(tr("Screens"))
            .build(),
    );
    tabs.add(
        adw::Toggle::builder()
            .name("windows")
            .label(tr("Windows"))
            .build(),
    );
    tabs.set_active_name(Some("screens"));
    let share = gtk::Button::builder()
        .label(tr("Share"))
        .css_classes(["suggested-action"])
        .sensitive(false)
        .build();

    let fill = {
        let (list, share, p) = (list.clone(), share.clone(), p.clone());
        move |tab: &str| {
            list.remove_all();
            if tab == "screens" {
                let monitors = gdk::Display::default()
                    .map(|d| d.monitors())
                    .into_iter()
                    .flat_map(|m| {
                        (0..m.n_items()).filter_map(move |i| {
                            m.item(i).and_then(|o| o.downcast::<gdk::Monitor>().ok())
                        })
                    });
                for m in monitors {
                    let name = m.connector().map(|c| c.to_string()).unwrap_or_default();
                    let model = m.model().map(|c| c.to_string()).unwrap_or_default();
                    let g = m.geometry();
                    let scale = m.scale();
                    let size = format!(
                        "{name}  ·  {} × {}",
                        (g.width() as f64 * scale).round(),
                        (g.height() as f64 * scale).round()
                    );
                    list.append(&row(
                        &screen_title(&name, &model),
                        &size,
                        None,
                        "video-display-symbolic",
                        &format!("screen:{name}"),
                    ));
                }
                list.append(&row(
                    &tr("Part of the screen"),
                    &tr("Draw it with the mouse"),
                    None,
                    "image-x-generic-symbolic",
                    "region",
                ));
            } else {
                let found = windows(&std::env::var("XDPH_WINDOW_SHARING_LIST").unwrap_or_default());
                if found.is_empty() {
                    let none = adw::ActionRow::builder()
                        .title(tr("No windows are open"))
                        .sensitive(false)
                        .build();
                    list.append(&none);
                }
                for w in found {
                    let (app_name, icon) = app_of(&w.app);
                    let title = if w.title.is_empty() {
                        w.app.clone()
                    } else {
                        w.title.clone()
                    };
                    list.append(&row(
                        &title,
                        &app_name,
                        icon,
                        "application-x-executable",
                        &format!("window:{}", w.id),
                    ));
                }
            }
            p.picked.borrow_mut().clear();
            share.set_sensitive(false);
            if let Some(first) = list
                .row_at_index(0)
                .filter(|r| r.widget_name() != "region" && r.is_sensitive())
            {
                list.select_row(Some(&first));
                first.grab_focus();
            }
        }
    };
    let f = fill.clone();
    tabs.connect_active_name_notify(move |t| f(t.active_name().as_deref().unwrap_or("screens")));

    let (p2, share2) = (p.clone(), share.clone());
    list.connect_row_selected(move |_, r| {
        let value = r
            .map(|r| r.widget_name().to_string())
            .filter(|v| v != "region")
            .unwrap_or_default();
        share2.set_sensitive(!value.is_empty());
        *p2.picked.borrow_mut() = value;
    });
    let p2 = p.clone();
    list.connect_row_activated(move |_, r| match r.widget_name().as_str() {
        "region" => p2.region(),
        value => p2.answer(value),
    });
    let click = gtk::GestureClick::new();
    let (p2, l2) = (p.clone(), list.clone());
    click.connect_released(move |_, n, _, y| {
        if n == 1
            && l2
                .row_at_y(y as i32)
                .is_some_and(|r| r.widget_name() == "region")
        {
            p2.region();
        }
    });
    list.add_controller(click);
    fill("screens");

    let cancel = gtk::Button::builder().label(tr("Cancel")).build();
    let p2 = p.clone();
    cancel.connect_clicked(move |_| p2.answer(""));
    let p2 = p.clone();
    share.connect_clicked(move |_| {
        let picked = p2.picked.borrow().clone();
        if !picked.is_empty() {
            p2.answer(&picked);
        }
    });

    let heading = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    heading.append(
        &gtk::Image::builder()
            .icon_name("video-display-symbolic")
            .pixel_size(32)
            .css_classes(["accent"])
            .build(),
    );
    let words = gtk::Box::new(gtk::Orientation::Vertical, 2);
    words.append(
        &gtk::Label::builder()
            .label(tr("Share your screen"))
            .xalign(0.0)
            .css_classes(["title-2"])
            .build(),
    );
    words.append(
        &gtk::Label::builder()
            .label(tr("An app asks to see your screen. Pick what it may see."))
            .xalign(0.0)
            .wrap(true)
            .css_classes(["dim-label"])
            .build(),
    );
    heading.append(&words);
    let options = gtk::ListBox::builder()
        .css_classes(["boxed-list"])
        .selection_mode(gtk::SelectionMode::None)
        .build();
    options.append(&p.remember);
    let buttons = gtk::Box::builder()
        .spacing(8)
        .halign(gtk::Align::End)
        .build();
    buttons.append(&cancel);
    buttons.append(&share);

    let body = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(16)
        .margin_top(12)
        .margin_bottom(20)
        .margin_start(20)
        .margin_end(20)
        .build();
    body.append(&heading);
    body.append(&tabs);
    body.append(
        &gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .child(&list)
            .build(),
    );
    body.append(&options);
    body.append(&buttons);
    let view = adw::ToolbarView::new();
    view.add_top_bar(&adw::HeaderBar::builder().show_title(false).build());
    view.set_content(Some(&body));

    let win = adw::ApplicationWindow::builder()
        .application(app)
        .title(tr("Share your screen"))
        .default_width(560)
        .default_height(560)
        .content(&view)
        .build();
    let p2 = p.clone();
    win.connect_close_request(move |_| {
        p2.answer("");
        glib::Propagation::Proceed
    });
    vyntaris_ui::escape_closes(&win);
    let keys = gtk::ShortcutController::new();
    let p2 = p.clone();
    let enter = gtk::CallbackAction::new(move |_, _| {
        let picked = p2.picked.borrow().clone();
        if picked.is_empty() {
            return glib::Propagation::Proceed;
        }
        p2.answer(&picked);
        glib::Propagation::Stop
    });
    keys.add_shortcut(gtk::Shortcut::new(
        gtk::ShortcutTrigger::parse_string("Return|KP_Enter"),
        Some(enter),
    ));
    win.add_controller(keys);
    let l2 = list.clone();
    win.connect_map(move |_| {
        if let Some(r) = l2.selected_row() {
            r.grab_focus();
        }
    });
    *p.win.borrow_mut() = Some(win.clone());
    win
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_portals_window_list_read() {
        let old =
            windows("94[HC>]firefox[HT>]Meeting — Mozilla Firefox[HE>]95[HC>]kitty[HT>]~[HE>]");
        assert_eq!(old.len(), 2);
        assert_eq!(
            (
                old[0].id.as_str(),
                old[0].app.as_str(),
                old[0].title.as_str()
            ),
            ("94", "firefox", "Meeting — Mozilla Firefox")
        );
        let new =
            windows("94[HC>]firefox[HT>]Meeting[HE>]0x55d1[HA>]95[HC>]kitty[HT>]~[HE>]0x55d2[HA>]");
        assert_eq!(new.len(), 2);
        assert_eq!(new[1].title, "~");
        assert!(windows("").is_empty());
    }

    #[test]
    fn screens_by_what_they_are() {
        vyntaris_core::i18n::english();
        assert_eq!(screen_title("eDP-1", "0x0ABC"), "Built-in screen");
        assert_eq!(screen_title("DP-2", "DELL U2720Q"), "DELL U2720Q");
        assert_eq!(screen_title("HDMI-A-1", "0x1234"), "HDMI-A-1");
        assert_eq!(screen_title("HDMI-A-1", ""), "HDMI-A-1");
    }
}
