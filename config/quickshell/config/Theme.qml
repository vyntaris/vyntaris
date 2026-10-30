pragma Singleton
import Quickshell
import QtQuick
import "Palettes.js" as Palettes

Singleton {
    id: root

    readonly property var basePalette: Palettes.palettes[Config.theme.flavor] ?? Palettes.palettes.mocha
    readonly property var palette: basePalette
    readonly property bool isDark: Config.theme.flavor !== "latte"
    readonly property var bootPalette: isDark ? basePalette : Palettes.palettes.mocha

    readonly property color rosewater: palette.rosewater
    readonly property color flamingo:  palette.flamingo
    readonly property color pink:      palette.pink
    readonly property color mauve:     palette.mauve
    readonly property color red:       palette.red
    readonly property color maroon:    palette.maroon
    readonly property color peach:     palette.peach
    readonly property color yellow:    palette.yellow
    readonly property color green:     palette.green
    readonly property color teal:      palette.teal
    readonly property color sky:       palette.sky
    readonly property color sapphire:  palette.sapphire
    readonly property color blue:      palette.blue
    readonly property color lavender:  palette.lavender
    readonly property color text:      palette.text
    readonly property bool highContrast: Config.accessibility.highContrast
    readonly property color subtext1:  highContrast ? palette.text : palette.subtext1
    readonly property color subtext0:  highContrast ? palette.text : palette.subtext0
    readonly property color overlay2:  highContrast ? palette.subtext1 : palette.overlay2
    readonly property color overlay1:  highContrast ? palette.subtext0 : palette.overlay1
    readonly property color overlay0:  highContrast ? palette.subtext0 : palette.overlay0
    readonly property color surface2:  palette.surface2
    readonly property color surface1:  palette.surface1
    readonly property color surface0:  palette.surface0
    readonly property color base:      palette.base
    readonly property color mantle:    palette.mantle
    readonly property color crust:     palette.crust

    readonly property string accentName: isDark ? Config.theme.accent : Config.theme.accentLight
    readonly property color accent:   Palettes.accent(palette, accentName)
    readonly property string accentNearest: Palettes.nearest(palette, accentName)
    function accentIn(pal) { return Palettes.accent(pal, accentName); }
    function colorOf(name) { return Palettes.accent(palette, name); }
    readonly property color textOnAccent: isDark ? crust : base
    readonly property color accentBright: Qt.lighter(accent, 1.18)
    readonly property color success:  green
    readonly property color error:    red
    readonly property color warning:  peach

    readonly property color glassTint:  crust
    readonly property color glass:      glassTint
    readonly property color glassTop:   isDark ? crust : mantle
    readonly property color glassRim:   alpha(text, highContrast ? 0.45 : isDark ? 0.14 : 0.16)
    readonly property color glassEdge:  isDark ? alpha("#ffffff", 0.24) : alpha(text, 0.14)
    readonly property color hairline: alpha(text, highContrast ? 0.3 : isDark ? 0.08 : 0.12)
    readonly property color hover:    alpha(text, isDark ? 0.06 : 0.08)

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property string fontFamily: Config.theme.fontFamily || Qt.application.font.family
    readonly property string monoFamily: Config.theme.monoFamily || "monospace"
    readonly property int fontSize: Config.theme.fontSize
    readonly property int fontSizeSmall: fontSize - 2
    readonly property real capsSpacing: 1.4

    readonly property int radius: 10

    readonly property int barHeight: Config.bar.height
    readonly property int panelTop: barHeight + 6
    readonly property int panelInset: 20
    readonly property bool squareBar: Config.bar.corners === "square"
    readonly property bool slanted: Config.bar.notchStyle === "slant"
    readonly property real islandCurves: Config.bar.inside === "sharp" ? 0 : Config.bar.inside === "soft" ? 0.5 : 1
    readonly property int shoulder: squareBar ? 0 : Math.round(16 * islandCurves)

    readonly property int notchWidth: 186
    readonly property int notchDepth: Config.bar.flatIsland ? 0 : 11
    readonly property int screenCorner: squareBar || Config.bar.endCorners === false ? 0 : Math.max(0, Config.bar.endCurve)
    readonly property int notchCorner: squareBar ? 0 : 4
    readonly property real shapeRoundness: squareBar ? 0 : Config.bar.endCurve >= 16 ? 1 : Config.bar.endCurve >= 10 ? 0.7 : 0.3
    readonly property int drawerRadius: squareBar ? 0 : Math.round(24 * shapeRoundness * islandCurves)
    readonly property real roundness: Config.bar.inside === "sharp" ? 0 : Config.bar.inside === "soft" ? Math.min(shapeRoundness, 0.5) : shapeRoundness
    function r(n) {
        return Math.round(n * roundness);
    }

    readonly property string animStyle: Config.theme.animationStyle
    readonly property bool calm: animStyle === "smooth" || animStyle === "snappy"
    readonly property real speed: Config.theme.animationSpeed * (animStyle === "snappy" ? 1.45 : 1)
    function duration(ms) {
        return speed > 0 ? Math.round(ms / speed) : 0;
    }
    readonly property int durationFast:   duration(140)
    readonly property int durationNormal: duration(260)
    readonly property int durationSlow:   duration(420)

    readonly property var curveStandard:   [0.2, 0, 0, 1, 1, 1]
    readonly property var curveDecelerate: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var curveSpring: animStyle === "snappy" ? [0.2, 1, 0.3, 1, 1, 1]
        : calm ? [0.25, 0.8, 0.25, 1, 1, 1] : [0.34, 1.32, 0.64, 1, 1, 1]

    readonly property int durationPanelIn: calm ? duration(340) : duration(500)
    readonly property int durationPanelOut: duration(260)
    readonly property int durationContentDelay: duration(90)
    readonly property int durationContentOut: duration(80)
    readonly property var curvePanelIn: animStyle === "snappy" ? [0.2, 1, 0.3, 1, 1, 1]
        : calm ? [0.25, 0.8, 0.25, 1, 1, 1]
        : [0.0417, 0, 0.0833, 0.1433, 0.125, 0.2843, 0.1667, 0.4254, 0.2083, 0.5694, 0.25, 0.6788, 0.2917, 0.7882, 0.3333, 0.8664, 0.375, 0.9183, 0.4167, 0.9702, 0.4583, 0.9971, 0.5, 1.0118, 0.5417, 1.0264, 0.5833, 1.029, 0.625, 1.0283, 0.6667, 1.0275, 0.7083, 1.0232, 0.75, 1.0192, 0.7917, 1.0151, 0.8333, 1.0112, 0.875, 1.0083, 0.9167, 1.0053, 0.9583, 1.0013, 1, 1]
    readonly property var curvePanelOut: [0.3, 0, 0.2, 1, 1, 1]
}
