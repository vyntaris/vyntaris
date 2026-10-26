#!/bin/sh
helper="$1"; pkg="$2"
state="${XDG_RUNTIME_DIR:-/tmp}/vyntaris-aur"
mkdir -p "$state" && rm -f "$state/$pkg" && log="$state/$pkg.log" && : > "$log"
end() { echo "$1" > "$state/$pkg"; exit 0; }
case "$pkg" in ""|*[!a-z0-9@._+-]*) end failed ;; esac

if ! pacman -Q base-devel >/dev/null 2>&1; then
    pkexec pacman -S --needed --noconfirm base-devel >> "$log" 2>&1
    case $? in 0) ;; 126|127) end cancelled ;; *) end failed ;; esac
fi
case "$helper" in
    paru) paru -S --noconfirm --skipreview --sudo pkexec "$pkg" >> "$log" 2>&1 ;;
    *) yay -S --noconfirm --answerclean None --answerdiff None --answeredit None --removemake \
           --sudo pkexec "$pkg" >> "$log" 2>&1 ;;
esac
pacman -Q "$pkg" >/dev/null 2>&1 && end ok
grep -qiE "not authorized|dismissed|authentication" "$log" && end cancelled
end failed
