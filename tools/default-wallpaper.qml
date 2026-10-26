import QtQuick
import "../config/quickshell/components/WallpaperArt.js" as Art
import "../config/quickshell/components/LogoArt.js" as LogoArt
import "../config/quickshell/config/Palettes.js" as Palettes

Item {
    Component.onCompleted: {
        const pal = Palettes.palettes.mocha;
        const colors = { crust: pal.crust, mantle: pal.mantle, base: pal.base, text: pal.text,
                         accent: Palettes.accent(pal, "blue"), partner: LogoArt.partner(pal, "blue"), dark: true };
        console.log("SVG" + Art.scene("minimal", 2560, 1440, colors));
        Qt.quit();
    }
}
