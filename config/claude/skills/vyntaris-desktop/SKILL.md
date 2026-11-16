---
name: vyntaris-desktop
description: Change the Vyntaris desktop itself — theme, accent, fonts, bar, island, wallpaper, keyboard, apps, shortcuts — and drive it (open panels, start a timer, notifications). Use whenever the user asks to change how their desktop looks or behaves, or to do something with the bar, island, launcher or settings on Vyntaris.
---

# The Vyntaris desktop

Vyntaris is Arch Linux with Hyprland and a Quickshell shell (bar + "island" at the top center). Prefer its own
settings and IPC over editing configs by hand: they apply live and survive updates.

## Settings: `~/.config/quickshell/settings.json`

One JSON file, watched by the shell: edit it and the change applies at once. Groups:
`theme apps input windows display bar wallpaper launcher notifications idle battery nightLight live gameMode
phone cloudBackup weather audio edges startup accessibility lock power passwords claude`.

Examples:
- `theme.flavor` (`mocha`, `macchiato`, `frappe`, `latte`), `theme.accent` (`mauve`, `blue`, `green`, …),
  `theme.fontFamily`, `theme.fontSize`, `theme.animationSpeed`
- `apps.terminal`, `apps.browser`, `apps.editor`, `apps.fileManager`
- `input.kbLayout` (`"us,rs"`), `input.naturalScroll`, `input.tapToClick`
- `windows.rounding`, `windows.gapsIn`, `windows.border`
- `bar.height`, `bar.clockFormat`, `bar.notchStyle`
- `wallpaper.directory`, `wallpaper.path`

Rules: read the file first, change only the keys asked for, keep it valid JSON, never drop unknown keys.
When unsure what a key does, open Settings on that page instead: `qs -c vyntaris ipc call settings page <name>`.

## Driving the shell: `qs -c vyntaris ipc call <target> <function> [args]`

- Panels: `island open <name>` / `island close` (`control`, `wifi`, `sound`, `wallpaper`, `timer`, `media`, …)
- `launcher query "<text>"`, `wiki search "<query>"`, `store search "<app>"`, `settings search "<text>"`
- `timer start 25m`, `timer stopwatch`
- `wallpaper set <path>`, `wallpaper random`
- `nightlight toggle`, `gamemode toggle`, `notifications silent`, `lock lock`
- `activity banner <icon> "<title>" "<subtitle>"` shows a short banner in the island — use it to say a long
  task is done.

`qs -c vyntaris ipc show` lists every target.

## Hyprland

The system config (`/usr/share/vyntaris/hypr/hyprland.lua`) is managed by the package; never edit it. Personal
binds, window rules and monitor settings go in `~/.config/hypr/user.lua` (Lua, loaded last, mistakes reported in
a notification). Check with `hyprctl reload` and `hyprctl configerrors`.
