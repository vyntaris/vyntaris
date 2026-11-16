---
name: vyntaris-system
description: Install, update or remove software and change system files safely on Vyntaris (Arch Linux) — pacman, AUR, services, snapshots and rolling back. Use before any sudo, pacman, AUR or systemctl work on Vyntaris, or when something broke after a change.
---

# Changing the system on Vyntaris

## Safety net

- Before the first system command in a session (`sudo`, `pacman -S/-R/-U`, `systemctl` without `--user`, …)
  Vyntaris takes a Timeshift snapshot by itself; the island says so. Every pacman upgrade gets one as well.
- The user approves each change in the island. Say in one line what a command does and why before asking.
- If something went wrong: snapshots are in Settings → Backups, or `sudo timeshift --list` /
  `sudo timeshift --restore`. Suggest restoring; don't restore without being asked.

## Software

- Repo packages: `sudo pacman -S --needed <pkg>`; remove with `sudo pacman -Rns <pkg>`.
- Search first: `pacman -Ss <word>`, `pacman -Qi <pkg>`.
- AUR: only if `apps.aur` is on in `~/.config/quickshell/settings.json`; use `yay` (never `sudo yay`).
- Flatpak apps are fine for desktop apps that aren't in the repos.
- Full upgrades go through the shell's Updates panel (`qs -c vyntaris ipc call updates open`), not `pacman -Syu`
  in a session: it checks the news and guards against a half-done upgrade.
- Never partial upgrades (`pacman -Sy <pkg>`).

## Services and files

- Prefer user services (`systemctl --user`) and files under `~/.config`.
- Files from the `vyntaris` package (`pacman -Qlq vyntaris`) are replaced on update: change them through a
  setting, a drop-in (`/etc/systemd/system/<unit>.d/`) or the user's own config instead.
- Logs: `journalctl -b -p warning`, `journalctl --user -u vyntaris-shell -n 50`.
