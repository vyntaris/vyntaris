#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key="$(cut -d: -f1 "$here/system/keyring/vyntaris-trusted")"
[ "$#" -gt 0 ] || { echo "usage: tools/publish-repo.sh PACKAGE.pkg.tar.zst..." >&2; exit 2; }
: "${R2_ACCESS_KEY_ID:?the key to R2: R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ACCOUNT_ID}"
pkgs=(); for p in "$@"; do pkgs+=("$(realpath "$p")"); done
export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true \
    RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
    RCLONE_CONFIG_R2_ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"
bucket="r2:${R2_PACKAGES_BUCKET:-vyntaris-packages}"
server="https://pkg.vyntarisos.com"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

pkgname() { bsdtar -xOf "$1" .PKGINFO | sed -n 's/^pkgname = //p'; }
published_db() { rclone hashsum md5 "$bucket" --include vyntaris.db 2>/dev/null | cut -d' ' -f1; }

mkdir -p "$work/repo"; cd "$work/repo"
base="$(published_db)"
rclone copy "$bucket" . --include '*.pkg.tar.zst' --include '*.pkg.tar.zst.sig'

names=(); for p in "${pkgs[@]}"; do names+=("$(pkgname "$p")"); done
for f in *.pkg.tar.zst; do
    [ -e "$f" ] || continue
    for n in "${names[@]}"; do
        if [ "$(pkgname "$f")" = "$n" ]; then rm -f "$f" "$f.sig"; break; fi
    done
done
for p in "${pkgs[@]}"; do
    cp "$p" .
    gpg --batch --yes --pinentry-mode loopback --passphrase '' --detach-sign --no-armor --local-user "$key" "$(basename "$p")"
done
repo-add -q --sign --key "$key" vyntaris.db.tar.gz ./*.pkg.tar.zst
rm -f vyntaris.db vyntaris.files vyntaris.db.sig vyntaris.files.sig
for f in db files; do
    cp "vyntaris.$f.tar.gz" "vyntaris.$f"; cp "vyntaris.$f.tar.gz.sig" "vyntaris.$f.sig"
done
cp "$here/system/keyring/vyntaris.gpg" vyntaris.gpg

check="$(mktemp -d)"
GNUPGHOME="$check" gpg --batch --quiet --import vyntaris.gpg
for f in ./*.pkg.tar.zst vyntaris.db vyntaris.files; do
    GNUPGHOME="$check" gpg --batch --status-fd 1 --verify "$f.sig" "$f" 2>/dev/null | grep -q "VALIDSIG $key" ||
        { echo "the signature of $f doesn't check out" >&2; exit 1; }
done
rm -rf "$check"
current=(); for f in ./*.pkg.tar.zst; do current+=("${f#./}"); done
published=(); for p in "${pkgs[@]}"; do published+=("$(basename "$p" .pkg.tar.zst)"); done
echo "signed and checked: ${current[*]}, vyntaris.db, vyntaris.files"
cat > index.html <<EOF
<!doctype html><meta charset="utf-8"><title>Vyntaris packages</title>
<body style="font:15px/1.6 system-ui;background:#1e1e2e;color:#cdd6f4;padding:3em;max-width:44em">
<h1 style="color:#cba6f7">Vyntaris packages</h1>
<p>The package repository of Vyntaris: pacman reads it. Current:</p>
<ul>$(printf '<li><code>%s</code></li>' "${current[@]}")</ul>
<p>Everything here is signed with Vyntaris's key, <a href="vyntaris.gpg" style="color:#89b4fa">vyntaris.gpg</a>
(<code>$key</code>):</p>
<pre style="background:#181825;padding:1em;border-radius:8px">sudo pacman-key --add vyntaris.gpg
sudo pacman-key --lsign-key $key

[vyntaris]
SigLevel = Required DatabaseOptional
Server = $server</pre>
EOF

if [ "$(published_db)" != "$base" ]; then
    tries="${PUBLISH_TRIES:-1}"
    [ "$tries" -lt 5 ] || { echo "the package repository kept changing under this; gave up" >&2; exit 1; }
    echo "the package repository changed meanwhile: again, on top of it" >&2
    cd /; rm -rf "$work"
    PUBLISH_TRIES=$((tries + 1)) exec "$here/tools/publish-repo.sh" "${pkgs[@]}"
fi
rclone copy . "$bucket" --exclude 'vyntaris.db*' --exclude 'vyntaris.files*' --exclude 'index.html'
rclone copy . "$bucket" --include 'vyntaris.db*' --include 'vyntaris.files*' --include 'index.html' \
    --header-upload 'Cache-Control: no-cache'
rclone sync . "$bucket"
echo "published ${published[*]} to $server"
