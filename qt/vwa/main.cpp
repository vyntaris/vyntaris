// VWA: WhatsApp Web in its own window, on Qt WebEngine (Chromium, so calls work).
#include <QApplication>
#include <QCloseEvent>
#include <QContextMenuEvent>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QMenu>
#include <QProcess>
#include <QRegularExpression>
#include <QShortcut>
#include <QStandardPaths>
#include <QStyleHints>
#include <QUrlQuery>
#include <QWebEngineDownloadRequest>
#include <QWebEngineNotification>
#include <QWebEnginePage>
#include <QWebEnginePermission>
#include <QWebEngineProfile>
#include <QWebEngineScript>
#include <QWebEngineScriptCollection>
#include <QWebEngineSettings>
#include <QWebEngineView>
#include <functional>
#include <map>
#include <memory>

static const QString NAME = "VWA";
static const QUrl HOME("https://web.whatsapp.com/");
static const QString SOCKET = "vyntaris-vwa";
static const QString AT_LOGIN = "vyntaris-vwa --background";

static QString env(const char *name, const QString &fallback) {
    QString v = qEnvironmentVariable(name);
    return v.startsWith('/') ? v : QDir::homePath() + "/" + fallback;
}
static QString configHome() { return env("XDG_CONFIG_HOME", ".config"); }
static QString settingsPath() { return configHome() + "/quickshell/settings.json"; }
static QString palettePath() { return configHome() + "/qt6ct/colors/shell.conf"; }

static QString shellDir() {
    QString own = configHome() + "/quickshell/vyntaris";
    return QFile::exists(own + "/shell.qml") ? own : "/etc/xdg/quickshell/vyntaris";
}

// The shell's translations.
static QJsonObject words() {
    QString locale;
    for (const char *v : {"VYNTARIS_LANG", "LC_MESSAGES", "LANG"})
        if (!(locale = qEnvironmentVariable(v)).isEmpty()) break;
    QString lang = locale.section(QRegularExpression("[_.@]"), 0, 0).toLower();
    if (lang.isEmpty() || lang == "c" || lang == "posix" || lang == "en") return {};
    QFile f(shellDir() + "/i18n/" + lang + ".json");
    return f.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(f.readAll()).object() : QJsonObject();
}
static QString T(const char *s) {
    static const QJsonObject dict = words();
    QString t = dict.value(QString::fromUtf8(s)).toString();
    return t.isEmpty() ? QString::fromUtf8(s) : t;
}

// red, blue and mauve from Qt's palette; yellow, pink and teal from the terminal's, which the shell writes too.
static QStringList hues(QStringList out) {
    QFile f(configHome() + "/kitty/theme.conf");
    if (f.open(QIODevice::ReadOnly))
        for (const QString &line : QString::fromUtf8(f.readAll()).split('\n')) {
            QStringList kv = line.split(' ', Qt::SkipEmptyParts);
            if (kv.size() == 2 && (kv[0] == "color3" || kv[0] == "color5" || kv[0] == "color6")) out << kv[1];
        }
    return out;
}

// Accent and window colour from the Qt palette the shell writes.
struct Look { QString accent; QColor window, text; bool dark; QStringList shades, hues; };
static Look look() {
    QFile f(palettePath());
    if (f.open(QIODevice::ReadOnly)) {
        for (const QString &line : QString::fromUtf8(f.readAll()).split('\n')) {
            if (!line.startsWith("active_colors=")) continue;
            QStringList c = line.mid(14).split(QRegularExpression(",\\s*"));
            if (c.size() > 20) {
                // crust, mantle, base, surface 0-2, overlay, text
                QStringList shades;
                for (int i : {4, 9, 10, 1, 3, 2, 20, 0}) shades << c[i].trimmed();
                return { c[12].trimmed(), QColor(c[10].trimmed()), QColor(c[0].trimmed()), QColor(c[10].trimmed()).lightness() < 128, shades,
                         hues({c[7].trimmed(), c[14].trimmed(), c[15].trimmed()}) };
            }
        }
    }
    return { "#cba6f7", QColor("#1e1e2e"), QColor("#cdd6f4"), true, {} };
}

// wa.me and whatsapp: links, opened in WhatsApp Web.
static QUrl webLink(const QString &link) {
    QUrl url(link);
    if (url.host() == HOME.host()) return url;
    QUrlQuery q(url);
    if (url.scheme() == "whatsapp" && url.host() == "send") {
        QUrl to = HOME.resolved(QUrl("send"));
        to.setQuery(q);
        return to;
    }
    QString phone = url.path().mid(1);
    if (url.host() == "wa.me" && !phone.isEmpty() && QRegularExpression("^\\d+$").match(phone).hasMatch()) {
        q.addQueryItem("phone", phone);
        QUrl to = HOME.resolved(QUrl("send"));
        to.setQuery(q);
        return to;
    }
    return HOME;
}

static QJsonObject readSettings() {
    QFile f(settingsPath());
    return f.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(f.readAll()).object() : QJsonObject();
}
static bool startsAtLogin() {
    for (const auto &a : readSettings()["startup"].toObject()["apps"].toArray())
        if (a.toObject()["command"].toString() == AT_LOGIN) return true;
    return false;
}
static void setAtLogin(bool on) {
    QJsonObject s = readSettings(), startup = s["startup"].toObject();
    QJsonArray apps;
    for (const auto &a : startup["apps"].toArray())
        if (a.toObject()["command"].toString() != AT_LOGIN) apps.append(a);
    if (on) apps.append(QJsonObject{{"name", NAME}, {"command", AT_LOGIN}});
    startup["apps"] = apps;
    s["startup"] = startup;
    QFile f(settingsPath() + ".tmp");
    if (f.open(QIODevice::WriteOnly) && f.write(QJsonDocument(s).toJson()) > 0) {
        f.close();
        QFile::remove(settingsPath());
        f.rename(settingsPath());
    }
}

static QString freeName(const QString &dir, QString name) {
    name = QFileInfo(name).fileName();
    if (name.isEmpty()) name = "download";
    QFileInfo fi(QDir(dir).filePath(name));
    if (!fi.exists()) return fi.fileName();
    QString stem = fi.completeBaseName(), ext = fi.suffix().isEmpty() ? "" : "." + fi.suffix();
    for (int i = 2;; i++) {
        QString n = QString("%1 (%2)%3").arg(stem).arg(i).arg(ext);
        if (!QFile::exists(QDir(dir).filePath(n))) return n;
    }
}

// Links that leave WhatsApp open in the browser.
class Page : public QWebEnginePage {
public:
    using QWebEnginePage::QWebEnginePage;
protected:
    bool acceptNavigationRequest(const QUrl &url, NavigationType type, bool main) override {
        if (main && type == NavigationTypeLinkClicked && url.host() != HOME.host()) {
            QDesktopServices::openUrl(url);
            return false;
        }
        return true;
    }
    void javaScriptConsoleMessage(JavaScriptConsoleMessageLevel, const QString &message, int line, const QString &source) override {
        if (qEnvironmentVariableIsSet("VWA_DEBUG")) qWarning("js %s:%d %s", qPrintable(source), line, qPrintable(message));
    }
    QWebEnginePage *createWindow(WebWindowType) override {
        auto *out = new QWebEnginePage(profile(), this);
        connect(out, &QWebEnginePage::urlChanged, out, [out](const QUrl &url) {
            if (url.isEmpty()) return;
            QDesktopServices::openUrl(url);
            out->deleteLater();
        });
        return out;
    }
};

class Window : public QWebEngineView {
public:
    Window(QWebEngineProfile *profile, const QColor &ground) {
        // The theme's colour until WhatsApp draws, not white.
        setPage(new Page(profile, this));
        page()->setBackgroundColor(ground);
        QPalette p = palette();
        p.setColor(QPalette::Window, ground);
        setPalette(p);
        setAutoFillBackground(true);
        setWindowTitle(NAME);
        setWindowIcon(QIcon::fromTheme("internet-chat"));
        resize(1100, 760);
        connect(this, &QWebEngineView::titleChanged, this, [this](const QString &t) {
            auto m = QRegularExpression("^\\((\\d+)\\)").match(t);
            setWindowTitle(m.hasMatch() ? QString("%1 (%2)").arg(NAME, m.captured(1)) : NAME);
        });
        connect(page(), &QWebEnginePage::permissionRequested, this, [](QWebEnginePermission p) { p.grant(); });
        new QShortcut(QKeySequence("Ctrl+R"), this, [this] { reload(); });
        new QShortcut(QKeySequence("F5"), this, [this] { reload(); });
        new QShortcut(QKeySequence("Ctrl+W"), this, [this] { hide(); });
        new QShortcut(QKeySequence("Ctrl+Q"), this, [] { qApp->quit(); });
    }
    void bringUp() {
        show();
        raise();
        activateWindow();
    }
protected:
    // Closing keeps it running, so messages still come in.
    void closeEvent(QCloseEvent *e) override {
        e->ignore();
        hide();
    }
    void contextMenuEvent(QContextMenuEvent *e) override {
        QMenu *menu = createStandardContextMenu();
        menu->addSeparator();
        menu->addAction(T("Reload"), this, [this] { reload(); });
        QAction *login = menu->addAction(T("Start at login"));
        login->setCheckable(true);
        login->setChecked(startsAtLogin());
        connect(login, &QAction::toggled, login, [](bool on) { setAtLogin(on); });
        menu->addAction(T("Quit"), qApp, &QApplication::quit);
        menu->setAttribute(Qt::WA_DeleteOnClose);
        menu->popup(e->globalPos());
    }
};

// Notifications go to the shell over org.freedesktop.Notifications; a click opens the chat.
class Notifier : public QObject {
    Q_OBJECT
public:
    explicit Notifier(Window *window) : window(window) {
        auto bus = QDBusConnection::sessionBus();
        bus.connect("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
                    "ActionInvoked", this, SLOT(invoked(uint, QString)));
        bus.connect("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
                    "NotificationClosed", this, SLOT(closed(uint, uint)));
    }
    uint send(const QString &title, const QString &body, std::function<void()> click = {}, uint replaces = 0) {
        QDBusMessage m = QDBusMessage::createMethodCall("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                                                        "org.freedesktop.Notifications", "Notify");
        QVariantMap hints{{"desktop-entry", "vwa"}};
        m << NAME << replaces << QString("internet-chat") << title << body
          << (click ? QStringList{"default", T("Open")} : QStringList{}) << hints << -1;
        QDBusMessage r = QDBusConnection::sessionBus().call(m, QDBus::Block, 2000);
        uint id = r.arguments().isEmpty() ? 0 : r.arguments().first().toUInt();
        if (id && click) clicks[id] = std::move(click);
        return id;
    }
    void chat(std::unique_ptr<QWebEngineNotification> n) {
        QWebEngineNotification *raw = n.get();
        uint id = send(n->title(), n->message(), [this, raw] {
            window->bringUp();
            for (auto &[k, v] : open) if (v.get() == raw) { v->click(); break; }
        });
        if (!id) return;
        // Kept after WhatsApp closes it (soon, or when another message comes): clicked from the island's list later, it
        // still opens that chat. Let go when the island closes it.
        n->show();
        open[id] = std::move(n);
    }
public slots:
    void invoked(uint id, const QString &) {
        auto it = clicks.find(id);
        if (it != clicks.end()) it->second();
    }
    void closed(uint id, uint) {
        clicks.erase(id);
        auto it = open.find(id);
        if (it != open.end()) { it->second->close(); open.erase(it); }
    }
private:
    Window *window;
    std::map<uint, std::function<void()>> clicks;
    std::map<uint, std::unique_ptr<QWebEngineNotification>> open;
};

static QString shadesJson(const Look &l) {
    return QString::fromUtf8(QJsonDocument(QJsonArray::fromStringList(l.shades)).toJson(QJsonDocument::Compact));
}

static QString huesJson(const Look &l) {
    return QString::fromUtf8(QJsonDocument(QJsonArray::fromStringList(l.hues)).toJson(QJsonDocument::Compact));
}

static QString accentScript(const Look &l) {
    QFile f(":/accent.js");
    if (!f.open(QIODevice::ReadOnly)) return {};
    return QString("window.__vyntarisAccent = \"%1\"; window.__vyntarisDark = %2; window.__vyntarisShades = %3; window.__vyntarisHues = %4;\n")
        .arg(l.accent, l.dark ? "true" : "false", shadesJson(l), huesJson(l)) + QString::fromUtf8(f.readAll());
}

// WhatsApp's loading screen is always light; it gets the theme's colours before anything draws, on every
// element, since WhatsApp sets some of them again further in.
static QString splashScript(const Look &l) {
    auto rgba = [](const QColor &c, double a) { return QString("rgba(%1, %2, %3, %4)").arg(c.red()).arg(c.green()).arg(c.blue()).arg(a); };
    QString w = l.window.name(), css = QString("* {"
        "--splashscreen-startup-background: %1 !important; --splashscreen-startup-background-plain: %1 !important;"
        "--splashscreen-startup-background-rgb: %2, %3, %4 !important; --splashscreen-primary-title: %5 !important;"
        "--splashscreen-startup-content-deemphasized: %6 !important; --splashscreen-secondary-lighter: %6 !important;"
        "--splashscreen-startup-icon: %7 !important; --splashscreen-progress-background: %7 !important;"
        "--splashscreen-progress-primary: %8 !important; } html, body { background: %1; }")
        .arg(w).arg(l.window.red()).arg(l.window.green()).arg(l.window.blue()).arg(l.text.name())
        .arg(rgba(l.text, 0.6), rgba(l.text, 0.1), l.accent);
    return QString("(() => { const s = new CSSStyleSheet(); s.replaceSync(`%1`);"
                   " document.adoptedStyleSheets = [...document.adoptedStyleSheets, s]; })();").arg(css);
}

int main(int argc, char **argv) {
    // Chromium takes light or dark at start. WhatsApp's calls need SharedArrayBuffer, which Chromium
    // keeps for isolated pages only; VWA loads nothing but WhatsApp.
    const Look now = look();
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS", qgetenv("QTWEBENGINE_CHROMIUM_FLAGS") + " --enable-features=SharedArrayBuffer"
        + (now.dark ? " --blink-settings=preferredColorScheme=0" : " --blink-settings=preferredColorScheme=1"));
    QApplication app(argc, argv);
    app.setApplicationName("vwa");
    app.setApplicationDisplayName(NAME);
    app.setDesktopFileName("vwa");
    app.setQuitOnLastWindowClosed(false);
    QStringList args = app.arguments().mid(1);
    bool background = args.contains("--background");
    QString link;
    for (const QString &a : args) if (a.contains(':')) link = a;

    // One VWA: a second start hands its link to the first.
    QLocalSocket other;
    other.connectToServer(SOCKET);
    if (other.waitForConnected(300)) {
        other.write((background ? "bg " : "fg ") + link.toUtf8() + "\n");
        other.waitForBytesWritten(300);
        return 0;
    }
    QLocalServer::removeServer(SOCKET);
    QLocalServer server;
    server.listen(SOCKET);

    app.styleHints()->setColorScheme(now.dark ? Qt::ColorScheme::Dark : Qt::ColorScheme::Light);

    QString data = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/vyntaris/vwa";
    QString cache = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + "/vyntaris/vwa";
    QWebEngineProfile profile("vwa");
    profile.setPersistentStoragePath(data);
    profile.setCachePath(cache);
    profile.setPersistentCookiesPolicy(QWebEngineProfile::ForcePersistentCookies);
    profile.setPersistentPermissionsPolicy(QWebEngineProfile::PersistentPermissionsPolicy::StoreOnDisk);
    // WhatsApp Web wants plain Chrome.
    profile.setHttpUserAgent(profile.httpUserAgent().remove(QRegularExpression("QtWebEngine/\\S+ ")));
    profile.setSpellCheckEnabled(true);
    profile.settings()->setAttribute(QWebEngineSettings::ScreenCaptureEnabled, true);

    QWebEngineScript accent;
    accent.setName("accent");
    accent.setInjectionPoint(QWebEngineScript::DocumentCreation);
    accent.setWorldId(QWebEngineScript::MainWorld);
    accent.setSourceCode(accentScript(now));
    profile.scripts()->insert(accent);
    QWebEngineScript splash;
    splash.setName("splash");
    splash.setInjectionPoint(QWebEngineScript::DocumentCreation);
    splash.setWorldId(QWebEngineScript::MainWorld);
    splash.setSourceCode(splashScript(now));
    profile.scripts()->insert(splash);

    Window window(&profile, now.window);
    Notifier notifier(&window);
    profile.setNotificationPresenter([&](std::unique_ptr<QWebEngineNotification> n) { notifier.chat(std::move(n)); });

    QObject::connect(&profile, &QWebEngineProfile::downloadRequested, &window, [&](QWebEngineDownloadRequest *d) {
        QString dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
        d->setDownloadDirectory(dir);
        d->setDownloadFileName(freeName(dir, d->suggestedFileName()));
        QObject::connect(d, &QWebEngineDownloadRequest::isFinishedChanged, &window, [&notifier, d, dir] {
            if (!d->isFinished()) return;
            if (d->state() == QWebEngineDownloadRequest::DownloadCompleted)
                notifier.send(T("Downloaded"), d->downloadFileName(), [dir] { QDesktopServices::openUrl(QUrl::fromLocalFile(dir)); });
            else if (d->state() == QWebEngineDownloadRequest::DownloadInterrupted)
                notifier.send(T("Couldn't download"), d->downloadFileName());
        });
        d->accept();
    });

    // A new accent or light/dark follows at once.
    QFileSystemWatcher watcher({palettePath()});
    QObject::connect(&watcher, &QFileSystemWatcher::fileChanged, &window, [&](const QString &path) {
        if (!watcher.files().contains(path)) watcher.addPath(path);
        Look l = look();
        if (l.dark != now.dark) {
            server.close();
            QProcess::startDetached(QCoreApplication::applicationFilePath(), window.isVisible() ? QStringList{} : QStringList{"--background"});
            app.quit();
            return;
        }
        accent.setSourceCode(accentScript(l));
        splash.setSourceCode(splashScript(l));
        profile.scripts()->remove(profile.scripts()->find("splash").value(0));
        profile.scripts()->insert(splash);
        profile.scripts()->remove(profile.scripts()->find("accent").value(0));
        profile.scripts()->insert(accent);
        window.page()->runJavaScript(QString("window.__vyntarisRecolour?.(\"%1\", %2, %3, %4)").arg(l.accent, l.dark ? "true" : "false", shadesJson(l), huesJson(l)));
    });

    auto open = [&](bool bg, const QString &to) {
        if (!to.isEmpty()) window.load(webLink(to));
        if (!bg) window.bringUp();
    };
    QObject::connect(&server, &QLocalServer::newConnection, &window, [&] {
        QLocalSocket *s = server.nextPendingConnection();
        QObject::connect(s, &QLocalSocket::readyRead, s, [s, &open] {
            QString line = QString::fromUtf8(s->readLine()).trimmed();
            open(line.startsWith("bg"), line.mid(3));
            s->deleteLater();
        });
    });

    window.load(link.isEmpty() ? HOME : webLink(link));
    if (!background) window.bringUp();
    return app.exec();
}

#include "main.moc"
