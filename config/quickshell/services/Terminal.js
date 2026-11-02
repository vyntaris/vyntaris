.pragma library

function screen(raw, rows) {
    const lines = [""];
    let row = 0, col = 0;
    const go = r => { row = Math.max(0, r); while (lines.length <= row) lines.push(""); };
    for (let i = 0; i < raw.length; i++) {
        const ch = raw[i];
        if (ch === "\x1b") {
            const m = /^\x1b\[([0-9;?]*)([A-Za-z])/.exec(raw.substr(i, 24));
            if (!m) continue;
            i += m[0].length - 1;
            const n = parseInt(m[1]) || 1;
            switch (m[2]) {
            case "A": go(row - n); break;
            case "B": go(row + n); break;
            case "F": go(row - n); col = 0; break;
            case "E": go(row + n); col = 0; break;
            case "G": col = n - 1; break;
            case "K": lines[row] = lines[row].slice(0, col); break;
            }
        } else if (ch === "\r") col = 0;
        else if (ch === "\n") { go(row + 1); col = 0; }
        else if (ch === "\b") col = Math.max(0, col - 1);
        else if (ch >= " ") {
            const l = lines[row] + " ".repeat(Math.max(0, col - lines[row].length));
            lines[row] = l.slice(0, col) + ch + l.slice(col + 1);
            col++;
        }
    }
    const shown = lines.map(l => l.replace(/\s+$/, ""));
    while (shown.length > 0 && shown[shown.length - 1] === "") shown.pop();
    return shown.slice(-rows).join("\n");
}
