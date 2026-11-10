// Logins as they're sent, for the island to offer saving them; and filling when the island asks.
(() => {
    const visible = el => el.offsetParent !== null || el.getClientRects().length > 0;
    const isUser = el => el instanceof HTMLInputElement && !el.disabled && visible(el)
        && ["text", "email", "tel", ""].includes(el.type) && el.autocomplete !== "one-time-code";
    const isPassword = el => el instanceof HTMLInputElement && el.type === "password" && !el.disabled && visible(el);

    // The username field before a password field: in its form, or on the page.
    function userFor(pw) {
        const scope = pw.form ? [...pw.form.elements] : [...document.querySelectorAll("input")];
        const before = scope.slice(0, scope.indexOf(pw)).filter(isUser);
        return before[before.length - 1] || null;
    }

    // Sites that ask the username on one page and the password on the next: the last one typed.
    let lastUser = "";
    document.addEventListener("change", e => {
        if (isUser(e.target) && e.target.value.trim()) lastUser = e.target.value.trim();
    }, true);

    let sent = "";
    function report(root) {
        const fields = [...(root || document).querySelectorAll("input")].filter(isPassword).filter(f => f.value);
        if (!fields.length) return;
        // A form with two or three password fields is a change or a sign-up: the new one is the last.
        const pw = fields[fields.length - 1];
        const u = userFor(fields[0]);
        const user = (u && u.value.trim()) || lastUser;
        const key = location.hostname + "\n" + user + "\n" + pw.value;
        if (key === sent) return;
        sent = key;
        browser.runtime.sendMessage({ type: "login", site: location.hostname, user, password: pw.value });
    }
    document.addEventListener("submit", e => report(e.target), true);
    document.addEventListener("click", e => {
        const b = e.target.closest && e.target.closest("button, input[type=submit], input[type=button], [role=button]");
        if (b) report(b.form || null);
    }, true);
    document.addEventListener("keydown", e => {
        if (e.key === "Enter" && e.target instanceof HTMLInputElement) report(e.target.form || null);
    }, true);

    // A login form's username field: the island offers this site's logins (password fields it finds itself).
    function atField(el) {
        if (!isUser(el) || el.value) return;
        const form = el.form ? [...el.form.elements] : [...document.querySelectorAll("input")];
        const pw = form.slice(form.indexOf(el) + 1).find(isPassword);
        const login = /user|login|email|account/i.test(el.name + " " + el.id + " " + el.autocomplete + " " + el.type);
        if (pw || login && el.autocomplete !== "off") browser.runtime.sendMessage({ type: "focus", site: location.hostname });
    }
    document.addEventListener("focusin", e => atField(e.target), true);
    // Focused by the page before this script came in (autofocus).
    if (document.hasFocus()) atField(document.activeElement);

    // Typed as if by hand, so the page's own scripts see it.
    function put(el, value) {
        el.focus();
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(el, value);
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
    }
    browser.runtime.onMessage.addListener(msg => {
        if (msg.type !== "fill" || !document.hasFocus()) return;
        const active = document.activeElement;
        // The focused field's own form first, not a sign-up form elsewhere on the page.
        const pw = isPassword(active) ? active
            : (active && active.form && [...active.form.elements].find(isPassword))
            || [...document.querySelectorAll("input")].find(isPassword);
        if (!pw) {
            // Only the username on this page.
            if (msg.user && isUser(active)) { put(active, msg.user); return Promise.resolve(true); }
            return;
        }
        const u = userFor(pw);
        if (msg.user && u && !u.value) put(u, msg.user);
        put(pw, msg.password);
        return Promise.resolve(true);
    });
})();
