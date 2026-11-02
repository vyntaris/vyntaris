import QtQuick
import "../../config/quickshell/services/Terminal.js" as Terminal

QtObject {
    property int fails: 0
    function is(what, raw, rows, want) {
        const got = Terminal.screen(raw, rows);
        const ok = got === want;
        console.log((ok ? "   ok    " : "   FAIL  ") + what + (ok ? "" : ` → ${JSON.stringify(got)}, wanted ${JSON.stringify(want)}`));
        if (!ok) fails++;
    }

    Component.onCompleted: {
        is("plain lines", "one\r\ntwo\r\n", 8, "one\ntwo");
        is("keeps only the last rows", "a\nb\nc\nd\n", 2, "c\nd");
        is("a carriage return draws over the line", "10%\r55%\r", 8, "55%");
        is("a shorter redraw keeps the rest", "upgrading\rdone", 8, "doneading");
        is("erase to the end of the line", "upgrading\r\x1b[Kdone", 8, "done");
        is("colours are dropped", "\x1b[1;31merror:\x1b[0m nope\r\n", 8, "error: nope");
        is("the cursor is hidden and shown", "\x1b[?25lbar\x1b[?25h", 8, "bar");
        is("parallel bars redraw in place", "a 10%\nb 20%\n\x1b[2Fa 90%\x1b[Kx\n\x1b[1Eb 99%", 8, "a 90%x\nb 20%\nb 99%");
        is("up past the top stays on the first line", "x\x1b[5Fy", 8, "y");
        is("candy bar", "(1/2) upgrading foo  [-----c o o]  50%\r(1/2) upgrading foo  [---------C-]  99%\r\n", 8,
            "(1/2) upgrading foo  [---------C-]  99%");
        console.log(fails === 0 ? "terminal: all pass" : `terminal: ${fails} failed`);
        Qt.exit(fails === 0 ? 0 : 1);
    }
}
