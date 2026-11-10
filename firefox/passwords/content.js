// Logins as they are sent, for the island to save; the icon in login fields; filling when the island asks.
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

    // The icon in a login field, as other password managers have: a click opens the island, every time.
    const cardField = el => el instanceof HTMLInputElement && !el.disabled && visible(el) && kindOf(el).startsWith("cc");
    const loginField = el => isPassword(el) || cardField(el) || isUser(el) && (
        [...(el.form ? el.form.elements : document.querySelectorAll("input"))].some(isPassword)
        || /user|login|email|account/i.test(el.name + " " + el.id + " " + el.autocomplete));
    let badge = null, badgeFor = null;
    // Styles the page's own CSS can't win against.
    const css = (el, props) => { for (const k in props) el.style.setProperty(k, props[k], "important"); };
    function place() {
        if (!badge || !badgeFor) return;
        const r = badgeFor.getBoundingClientRect(), s = Math.max(16, Math.min(22, r.height - 10));
        css(badge, {
            width: s + "px", height: s + "px",
            left: r.right - s - 8 + "px", top: r.top + (r.height - s) / 2 + "px",
        });
    }
    function showBadge(el) {
        if (!badge) {
            // The Vyntaris mark with a key on its corner, drawn in the page: no file for the page's rules to block.
            badge = document.createElement("vyntaris-passwords");
            badge.title = "Vyntaris Passwords";
            css(badge, {
                position: "fixed", "z-index": "2147483647", cursor: "pointer", margin: "0", padding: "0",
                border: "0", background: "none", "box-shadow": "none", display: "block", opacity: "1",
                visibility: "visible", "pointer-events": "auto", transform: "none",
            });
            const ns = "http://www.w3.org/2000/svg";
            const svg = document.createElementNS(ns, "svg");
            svg.setAttribute("viewBox", "0 0 24 24");
            svg.setAttribute("width", "100%");
            svg.setAttribute("height", "100%");
            svg.setAttribute("overflow", "visible");
            const el = (name, attrs) => {
                const e = document.createElementNS(ns, name);
                for (const k in attrs) e.setAttribute(k, attrs[k]);
                return e;
            };
            const mark = el("g", {});
            // The key: on its own in the accent's circle, until the mark comes in (and if it can't).
            const corner = el("g", { transform: "translate(12.5 12.5) scale(0.48)" });
            // The system's accent (through the style object: the page's rules can block a style attribute).
            const accent = el("circle", { cx: "12", cy: "12", r: "10.5", fill: "#cba6f7" });
            accent.style.setProperty("fill", "AccentColor");
            corner.append(
                el("circle", { cx: "12", cy: "12", r: "12", fill: "#1e1e2e" }),
                accent,
                el("path", { fill: "#1e1e2e", "fill-rule": "evenodd",
                    d: "M9.5 14.5a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5zm4.3-4A4.5 4.5 0 1 0 13.8 13.5H15v2h2v-2h1.5v-3z" }));
            svg.append(mark, corner);
            fetch(browser.runtime.getURL("icon.svg")).then(r => r.text()).then(text => {
                const logo = new DOMParser().parseFromString(text, "image/svg+xml").documentElement;
                if (logo.localName !== "svg") return;
                logo.setAttribute("width", "21");
                logo.setAttribute("height", "21");
                mark.append(document.importNode(logo, true));
            }).catch(() => {
                corner.setAttribute("transform", "");
            });
            badge.attachShadow({ mode: "closed" }).append(svg);
            // The field keeps the focus, so the fill lands in it.
            badge.addEventListener("mousedown", e => { e.preventDefault(); e.stopPropagation(); }, true);
            badge.addEventListener("click", e => {
                e.preventDefault();
                e.stopPropagation();
                const f = badgeFor;
                if (!f) return;
                const u = isPassword(f) ? userFor(f) : null;
                browser.runtime.sendMessage({
                    type: "open", site: location.hostname, field: cardField(f) ? "card" : isPassword(f) ? "password" : "user",
                    user: !!u, userEmpty: !!u && !u.value, signup: isSignUp(f),
                });
            }, true);
        }
        badgeFor = el;
        (document.body || document.documentElement).appendChild(badge);
        place();
    }
    function hideBadge() {
        badgeFor = null;
        if (badge) badge.remove();
    }
    // A sign-up or a change of password: the fields for the new one (the new one and its repeat).
    const NEW = /new|confirm|repeat|retype|again|sign.?up|regist|create|join|registr|napravi|novi/i;
    // The page or its button says it: "/signup", "Create account", "Registracija".
    const signUpPage = form => NEW.test(location.pathname + " " + location.search)
        || [...(form || document).querySelectorAll("button, input[type=submit]")]
            .some(b => /sign.?up|regist|create.*account|join|napravi.*nalog|registr/i.test(b.textContent + " " + b.value));
    function newFields(pw) {
        if (!isPassword(pw) || /current-password/.test(pw.autocomplete)) return [];
        const all = [...(pw.form ? pw.form.elements : document.querySelectorAll("input"))].filter(isPassword)
            .filter(f => !/current-password/.test(f.autocomplete));
        const marked = all.filter(f => /new-password/.test(f.autocomplete));
        if (marked.length) return marked.includes(pw) ? marked : [];
        const form = pw.form;
        const named = f => NEW.test(f.name + " " + f.id + " " + f.placeholder)
            || form && NEW.test((form.id || "") + " " + (form.getAttribute("action") || "") + " " + (form.className || ""));
        // Three: the current one, then the new one twice.
        const fresh = all.length >= 3 ? all.slice(1) : all.length === 2 || all.some(named) || signUpPage(form) ? all : [];
        return fresh.includes(pw) ? fresh : [];
    }
    // 20 characters, the same kinds as the island's (pass.sh generate), each kind at least once.
    function strong() {
        const sets = ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", "0123456789", "!#%+=?@^_-"];
        const every = sets.join("");
        const pick = (set, n) => {
            const out = [];
            const r = new Uint32Array(1);
            while (out.length < n) {
                crypto.getRandomValues(r);
                if (r[0] < Math.floor(2 ** 32 / set.length) * set.length) out.push(set[r[0] % set.length]);
            }
            return out;
        };
        for (;;) {
            const p = pick(every, 20);
            if (sets.every(set => p.some(c => set.includes(c)))) return p.join("");
        }
    }
    const SR = /^(sr|hr|bs)/i.test(browser.i18n.getUILanguage());
    let chip = null, chipFor = null, offered = "", filling = false;
    function placeChip() {
        if (!chip || !chipFor) return;
        const r = chipFor.getBoundingClientRect();
        css(chip, { left: r.left + "px", top: r.bottom + 4 + "px" });
    }
    function showChip(pw) {
        if (!chip) {
            chip = document.createElement("vyntaris-strong-password");
            css(chip, {
                position: "fixed", "z-index": "2147483647", cursor: "pointer", display: "flex", "align-items": "center",
                gap: "8px", padding: "8px 12px", margin: "0", "border-radius": "10px", border: "1px solid AccentColor",
                background: "#1e1e2e", color: "#cdd6f4", "box-shadow": "0 4px 16px rgba(0,0,0,.35)",
                font: "13px/1.3 system-ui, sans-serif", "max-width": "360px", visibility: "visible", opacity: "1",
            });
            const root = chip.attachShadow({ mode: "closed" });
            const label = document.createElement("span");
            label.textContent = SR ? "Preporučena lozinka" : "Recommended password";
            label.style.setProperty("font-weight", "600");
            const shown = document.createElement("span");
            shown.style.setProperty("font-family", "ui-monospace, monospace");
            shown.style.setProperty("color", "AccentColor");
            root.append(label, shown);
            chip.shown = shown;
            chip.addEventListener("mousedown", e => { e.preventDefault(); e.stopPropagation(); }, true);
            chip.addEventListener("click", e => {
                e.preventDefault();
                e.stopPropagation();
                const fields = newFields(chipFor), password = offered;
                hideChip();
                filling = true;
                for (const f of fields) put(f, password);
                filling = false;
            }, true);
        }
        offered = strong();
        chip.shown.textContent = offered;
        chipFor = pw;
        (document.body || document.documentElement).appendChild(chip);
        placeChip();
    }
    function hideChip() {
        chipFor = null;
        if (chip) chip.remove();
    }

    addEventListener("scroll", () => { place(); placeChip(); }, true);
    addEventListener("resize", () => { place(); placeChip(); });

    function focused(el) {
        if (loginField(el)) showBadge(el); else hideBadge();
        if (!filling && isPassword(el) && !el.value && newFields(el).length) showChip(el); else hideChip();
    }
    document.addEventListener("focusin", e => focused(e.target), true);
    document.addEventListener("focusout", e => {
        if (e.target === badgeFor) hideBadge();
        if (e.target === chipFor) hideChip();
    }, true);
    // Typing one in by hand: the offer goes.
    document.addEventListener("input", e => { if (e.isTrusted && e.target === chipFor) hideChip(); }, true);
    // Focused by the page before this script came in (autofocus).
    if (document.hasFocus()) focused(document.activeElement);

    // Typed as if by hand, so the page's own scripts see it.
    function put(el, value) {
        el.focus();
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(el, value);
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
        tint(el);
    }
    // A filled field in the system's accent, see-through, until it's typed in.
    function tint(el) {
        el.style.setProperty("background-color", "color-mix(in srgb, AccentColor 28%, transparent)", "important");
        el.style.setProperty("background-image", "none", "important");
        el.addEventListener("input", function untint(e) {
            if (!e.isTrusted) return;
            el.style.removeProperty("background-color");
            el.style.removeProperty("background-image");
            el.removeEventListener("input", untint);
        });
    }
    // A sign-up: the field's form makes a new password, or the page says so.
    function isSignUp(f) {
        const scope = [...(f.form ? f.form.elements : document.querySelectorAll("input"))];
        const pw = isPassword(f) ? f : scope.find(isPassword);
        return !!pw && newFields(pw).length > 0 || signUpPage(f.form);
    }

    // Personal info or a card into every field of the form that asks for it (a password is the offer under its field).
    const KINDS = [
        // [kind, autocomplete tokens, words in the field's name, id, placeholder or label]. Cards first: their
        // "name on card" isn't the person's name.
        ["ccnumber", ["cc-number"], /card.?num|cc.?num|cardnumber|broj.?kartic/i],
        ["cccsc", ["cc-csc"], /\bcvc|\bcvv|\bcsc|security.?code|sigurnosn/i],
        ["ccmonth", ["cc-exp-month"], /exp.*month|cc.?month|mesec.?isteka|mjesec.?isteka/i],
        ["ccyear", ["cc-exp-year"], /exp.*year|cc.?year|godina.?isteka/i],
        ["ccexp", ["cc-exp"], /expir|exp.?date|valid.?(thru|until)|mm.?\/.?yy|istek|va[zž]i do/i],
        ["ccname", ["cc-name"], /name.?on.?card|card.?holder|cardholder|holder|ime.?na.?kartic|vlasnik/i],
        ["email", ["email"], /e-?mail|mejl/i],
        ["phone", ["tel", "tel-national", "mobile"], /phone|mobile|^tel|telefon|mobilni/i],
        ["username", ["username", "nickname"], /user.?name|login|nick|korisni/i],
        ["postal", ["postal-code"], /zip|postal|post.?code|po[sš]tans|pttbroj/i],
        ["city", ["address-level2"], /city|town|grad|mesto|mjesto/i],
        ["country", ["country", "country-name"], /country|dr[zž]ava/i],
        ["company", ["organization"], /company|organi[sz]ation|firma|preduze/i],
        ["address", ["street-address", "address-line1"], /address|street|adresa|ulica/i],
        ["name", ["name"], /full.?name|^name$|your.?name|ime i prezime|ime_prezime/i],
        ["first", ["given-name"], /first.?name|fname|given|^ime\b/i],
        ["last", ["family-name"], /last.?name|lname|surname|family|prezime/i],
    ];
    function kindOf(el) {
        const tokens = (el.getAttribute("autocomplete") || "").toLowerCase().split(/\s+/);
        for (const [kind, auto] of KINDS) if (auto.some(t => tokens.includes(t))) return kind;
        if (el.type === "email") return "email";
        if (el.type === "tel") return "phone";
        const label = el.labels && el.labels[0] ? el.labels[0].textContent : "";
        const parts = [el.name, el.id, el.placeholder, el.getAttribute("aria-label"), label]
            .filter(Boolean).map(t => t.trim());
        for (const [kind, , words] of KINDS) if (parts.some(t => words.test(t))) return kind;
        return "";
    }
    // A select's option for a value: the same text, or the same number ("03" and "3", "2028" and "28").
    function option(el, v) {
        const same = t => t.toLowerCase() === v.toLowerCase();
        const n = parseInt(v, 10);
        return [...el.options].find(o => same(o.value) || same(o.textContent.trim()))
            || !isNaN(n) && [...el.options].find(o => [o.value, o.textContent.trim()].some(t =>
                parseInt(t, 10) === n || /^\d{4}$/.test(t) && v.length === 2 && t.endsWith(v)));
    }
    function fillFields(who) {
        const active = document.activeElement;
        const form = active && active.form;
        const fields = [...(form ? form.elements : document.querySelectorAll("input, select"))]
            .filter(el => !el.disabled && visible(el) && (el instanceof HTMLSelectElement
                || el instanceof HTMLInputElement && ["text", "email", "tel", ""].includes(el.type)));
        const [month, year] = (who.expiry || "").split(/\s*[\/.-]\s*/);
        const value = kind => kind === "name" ? [who.first, who.last].filter(Boolean).join(" ")
            : kind === "username" ? who.username || who.email || ""
            : kind === "ccnumber" ? (who.number || "").replace(/\s+/g, "")
            : kind === "ccname" ? who.holder || ""
            : kind === "ccexp" ? who.expiry || ""
            : kind === "ccmonth" ? month || ""
            : kind === "ccyear" ? year || ""
            : kind === "cccsc" ? who.cvv || ""
            : who[kind] || "";
        let filled = 0;
        filling = true;
        for (const el of fields) {
            const v = value(kindOf(el));
            if (!v) continue;
            if (el instanceof HTMLSelectElement) {
                const o = option(el, v);
                if (!o) continue;
                el.value = o.value;
                el.dispatchEvent(new Event("change", { bubbles: true }));
                tint(el);
            } else if (!el.value) put(el, v);
            else continue;
            filled++;
        }
        filling = false;
        if (active && active.focus) active.focus();
        return filled > 0;
    }

    browser.runtime.onMessage.addListener(msg => {
        if (msg.type !== "fill" || !document.hasFocus()) return;
        if (msg.fields) return fillFields(msg.fields) ? Promise.resolve(true) : undefined;
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
