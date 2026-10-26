# Security

## Reporting a problem

Please don't open a public issue for a security problem. Report it privately instead:

- on GitHub: **Security → Report a vulnerability**
  (https://github.com/vyntaris/vyntaris/security/advisories/new), or
- by e-mail to vyntarisos@gmail.com.

Say what is affected, how to reproduce it, and what someone could do with it. You'll get an answer within a
week. Once a fix is published, the advisory is made public, with your name if you want it there.

## What counts

Vyntaris's own code in this repository: the shell, the login and lock screens, the installer, the setup
scripts, safe updates, the apps and helpers in `rust/`, the package and its signing. For example: a way
around the lock screen, a helper run as root that can be made to do more than it should, a package or ISO
that installs without its signature checked, or a report from Dr. Help that leaks what it should take out.

A problem in Arch Linux, Hyprland, Quickshell or another package Vyntaris installs belongs to that project.
If you're not sure whose it is, report it here and we'll pass it on.

## Versions

Only the newest version gets fixes. Vyntaris is a rolling release: `pacman -Syu` brings every installed
system up to date.

## Signing key

Packages, the repository database and the ISO's checksums are signed with
`567CCD912301A261B06DAFFFC0905C46984D9F8B` (`system/keyring/vyntaris.gpg`, also at
https://vyntarisos.com/vyntaris.gpg).
