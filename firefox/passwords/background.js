// Between the pages and the island: logins go out, fills come in (through vyntaris_passwords).
let port = null;

function connect() {
    port = browser.runtime.connectNative("vyntaris_passwords");
    port.onMessage.addListener(async msg => {
        if (msg.type !== "fill") return;
        // The page with the focus, in whichever window has it.
        const tabs = await browser.tabs.query({ active: true });
        const answers = await Promise.all(tabs.map(t =>
            browser.tabs.sendMessage(t.id, { type: "fill", user: msg.user, password: msg.password }).catch(() => false)));
        port.postMessage({ type: "filled", id: msg.id, ok: answers.some(Boolean) });
    });
    port.onDisconnect.addListener(() => { port = null; setTimeout(connect, 5000); });
}
connect();

browser.runtime.onMessage.addListener(msg => {
    if (msg.type === "login" && port && msg.password) port.postMessage(msg);
    if (msg.type === "focus" && port) port.postMessage(msg);
});
