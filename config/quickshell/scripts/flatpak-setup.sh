#!/bin/sh
# Flathub for the Store: flatpak itself once (it asks for the password), then Flathub for this user, so apps
# install and update without one. The log is in $XDG_RUNTIME_DIR/vyntaris-flatpak-setup.log.
log="${XDG_RUNTIME_DIR:-/tmp}/vyntaris-flatpak-setup.log"
: > "$log"
if ! command -v flatpak >/dev/null 2>&1; then
    pkexec pacman -S --needed --noconfirm flatpak >> "$log" 2>&1 || exit 1
fi
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >> "$log" 2>&1
