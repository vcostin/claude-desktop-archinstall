#!/usr/bin/env bash
# claude-desktop on Arch — one-shot installer / updater.
#
# Fetches the latest official Claude Desktop .deb straight from Anthropic's
# apt repo, verifies it, and lays it down as an isolated, rootless install in
# your home folder. Then applies the Arch-specific adaptation the Debian
# package can't do itself: the pacman dependencies and the compatibility
# symlinks (OVMF firmware + virtiofsd) that the app probes for at Debian
# paths — i.e. it makes the .deb behave like a native Arch install, Cowork
# included. sudo is used only for those system steps, and only when something
# is actually missing (it prompts for your password then).
#
# Quick install (reads the latest from GitHub):
#   curl -fsSL https://raw.githubusercontent.com/vcostin/claude-desktop-archinstall/main/install.sh | bash
# Pass flags through a pipe with `bash -s --`:
#   curl -fsSL .../install.sh | bash -s -- --force
#
# Usage:
#   ./install.sh              # install or update to the latest
#   ./install.sh --force      # reinstall even if already current
#   ./install.sh --no-cowork  # skip QEMU/virtiofsd Arch adaptation
#   ./install.sh --dir PATH   # install dir (default ~/Apps/claude-desktop)
#   ./install.sh --deb FILE   # use a local .deb instead of downloading
#   ./install.sh --insecure-skip-verify  # skip GPG signature check (discouraged)
#   ./install.sh --check      # verify repo signature only, then exit (no install)
set -euo pipefail

# ---------------------------------------------------------------- config ----
APP="$HOME/Apps/claude-desktop"
REPO="https://downloads.claude.ai/claude-desktop/apt/stable"
ARCH="amd64"
VERIFY=1
# Anthropic's apt-repo signing key fingerprint ("Claude Code Release Signing").
# The full public key is pinned inline below (see anthropic_key). You can verify
# this is genuine independently: the identical key ships inside the official
# .deb's postinst script, and is published at
# https://downloads.claude.ai/.../claude-desktop-archive-keyring.asc
PINNED_FP="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
# Where this script lives upstream, so a `curl | bash` run can drop a copy of
# itself next to the app for future updates.
SELF_URL="https://raw.githubusercontent.com/vcostin/claude-desktop-archinstall/main/install.sh"
DO_COWORK=1
FORCE=0
LOCAL_DEB=""
CHECK_ONLY=0

# Arch adaptation symlinks the app probes for at Debian paths. virtiofsd points
# into the app payload (the bundled binary); the firmware target comes from the
# edk2-ovmf package.
ovmf_shim()  { echo "/usr/share/OVMF/OVMF_CODE_4M.fd|/usr/share/edk2/x64/OVMF_CODE.4m.fd"; }
viofs_shim() { echo "/usr/bin/virtiofsd|$APP/resources/virtiofsd"; }

# ----------------------------------------------------------------- args -----
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --no-cowork) DO_COWORK=0 ;;
    --dir) APP="$2"; shift ;;
    --deb) LOCAL_DEB="$2"; shift ;;
    --insecure-skip-verify) VERIFY=0 ;;
    --check) CHECK_ONLY=1 ;;
    -h|--help) sed -n '2,30p' "$0" 2>/dev/null || echo "see https://github.com/vcostin/claude-desktop-archinstall"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# --------------------------------------------------------------- helpers ----
c_blue=$'\033[1;34m'; c_grn=$'\033[1;32m'; c_yel=$'\033[1;33m'; c_red=$'\033[1;31m'; c_off=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s  !%s %s\n' "$c_yel" "$c_off" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "required tool missing: $1"; }

# Run a command as root, caching credentials so the password is asked once.
ROOT_PRIMED=0
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; return; fi
  need sudo
  if [ "$ROOT_PRIMED" -eq 0 ]; then
    log "A system step needs root — enter your sudo password if prompted."
    sudo -v || die "sudo authentication failed"
    ROOT_PRIMED=1
  fi
  sudo "$@"
}

# version_le A B  -> true if A <= B (numeric, dot-separated; uses sort -V)
version_le() { [ "$1" = "$2" ] || [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }

for t in curl bsdtar ar xz sha256sum sort awk; do need "$t"; done

# ------------------------------------------------- pinned signing key -------
# Anthropic "Claude Code Release Signing" public key (fingerprint $PINNED_FP),
# pinned in-script so trust does not depend on fetching a key over the network.
anthropic_key() {
cat <<'KEY_EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGnK73ABEACnbytJXkjweYrwIr0aLEFRlH+C0nF44KxFc7gQmJ6PjSPMGZAD
dxZcaixU7zZl8WxEpVO0wLmIH8cf2zGOdyuZg1Yaugk1vHb2b8WBhAGCQJdPgB8W
XquedepEYtk56uP/gCoTjJDUZluEGBHnlnuujSJ4orxEdhSykEoAUfJZGEILPpMd
bphFt/Sn+Eb/TxM5jpKPdwnv8AShNF/1mZU1fWTQq9tRKJUakZj04gdaDFElQXak
CtTij+GT6yoYCARSHwGO+PC/Pr6q4tc+D7LRjxSBvUWDoFSmlqb/PJ1hj9D/7I2O
e4XXniAPWMR56KvxHlzOzrNQdJujbJdSkCwh1ZijkSd3y8ayW5WYUTGdRab99NUw
agzlabe/VVF6kzJ0Scn5q3PihB2Y9Bwo0CKnkYk7a7KT77EWv0Kkq+VHmOtqX3a2
hhX+b6a6ve9rzJ1qZYGj+obv/C3Sx1LzUjAfqVy7RJDf2uAoP5t2g8u/TkSpUxhM
VEjZBkSxYZhMyzQM6t8IgkUfnSrIPTHixbDWARZ4beMOBjxyPZK1nP7OOrNR3TkK
JtwLMQAabURCDnL0PjS0iwBTU4jtumBD1XSULyWuoTvMljrpQr1nV1oDyOt0OLqa
KA2McWtd9PdXhC8y2EIg7TmrTlJLfHYbdmkiCYj4J49Q8HWkN/6WE+RTUwARAQAB
tD5BbnRocm9waWMgQ2xhdWRlIENvZGUgUmVsZWFzZSBTaWduaW5nIDxzZWN1cml0
eUBhbnRocm9waWMuY29tPokCUQQTAQoAOxYhBDHd3iTd+rZ59C170rqpKf8afsrO
BQJpyu9wAhsPBQsJCAcCAiICBhUKCQgLAgQWAgMBAh4HAheAAAoJELqpKf8afsrO
l5IP/2I8X1dFy5xYczWB/coIxGjuzS/V6ByZGZZEJsbr04pmuHiFUykJqPGWGQ6q
U0YF5iEwvEkaagS5m7DzhSEf3FM3Cgafax/6d70tar9Vr1D+w6uPfxetu7u/WYJp
aolIsdh5fTrBh9zSM1Njl8FM8wG8CwZQjS33Oa7d8cwRkgdUWbt6LXgz+cTQNuBn
BgW6Ks7oZFI25dfu0ojDR+aDFJg4+4wZoyDLPvJz1SIrJ5WFGs67zsx9SfS3yZnf
XKmBe+f0dUy+GJ2nFZrXFf99+c0dPEHYO8DCeAHZizjkFrdYtUHdDU0YDYEGkLJa
bE+pgcpkHf5EvsZzHsyDbl95W/eh7pcXMbwkN+W4CBYUE9X4uHhqzWaC5yAVRWUA
1BJ9V4LjZfHPLEJt0I3TxzXiEg9/BVeaTYq9RjaxIFo9Nfk158HqJY6SA5jslBlx
Gv/No8u+xVcze2UJyGVfEIUfm92+0UAIkny3+5cuVV0ICzJxXlXj0CnLM9Lt50wE
p3suVwuBEviCbZ08eAH1Ht8gbBdSsiOkIU8CX3v/scwHHx5q0+NBL6xLrQObg13a
tRXBlKObfElkPN3lTUbUnJOW4U8uSjH8VRP+AujKWMDFe7x0zCs+iYY1mTOvbrTS
9n3CmZUmbynZ+E/QWNENpW/pDNZdWFy43PASmML5FHu4m9Sn
=oqMI
-----END PGP PUBLIC KEY BLOCK-----
KEY_EOF
}

# Fetch the package index and verify it chains from the pinned key:
#   pinned key → InRelease (GPG signature) → Release → SHA256(Packages).
# Leaves a trusted $TMP/Packages behind. From there each .deb carries its own
# SHA256 in the (now-verified) index, completing the chain to the download.
fetch_verified_index() {
  if [ "$VERIFY" -eq 0 ]; then
    warn "signature verification DISABLED (--insecure-skip-verify) — not recommended"
    curl -fsSL "$REPO/dists/stable/main/binary-$ARCH/Packages" -o "$TMP/Packages" \
      || die "could not fetch package index"
    return
  fi
  need gpg
  log "Verifying repository signature against pinned Anthropic key $PINNED_FP …"
  export GNUPGHOME="$TMP/gnupg"; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
  anthropic_key | gpg --batch --quiet --import 2>/dev/null || die "failed to import pinned key"
  curl -fsSL "$REPO/dists/stable/InRelease" -o "$TMP/InRelease" || die "could not fetch InRelease"
  gpg --batch --status-fd 3 --output "$TMP/Release" --decrypt "$TMP/InRelease" 3>"$TMP/gpgstatus" 2>/dev/null \
    || die "InRelease signature verification FAILED"
  # VALIDSIG's LAST field is the primary key fingerprint; the first is the
  # signing (sub)key. Matching the primary means routine subkey rotation under
  # the same primary key keeps verifying without any change to this script —
  # only a full primary-key rotation would require updating the pinned key.
  primary_fpr="$(awk '$2=="VALIDSIG"{print $NF; exit}' "$TMP/gpgstatus")"
  [ "$primary_fpr" = "$PINNED_FP" ] \
    || die "InRelease is not signed by the pinned Anthropic key (got '${primary_fpr:-none}') — refusing to proceed"
  ok "repository signature valid (signed by Anthropic)"
  local want
  want=$(awk '/^SHA256:/{f=1;next} /^[^ ]/{f=0} f && $3=="main/binary-'"$ARCH"'/Packages"{print $1}' "$TMP/Release" | head -1)
  [ -n "$want" ] || die "signed Release has no SHA256 for binary-$ARCH/Packages"
  curl -fsSL "$REPO/dists/stable/main/binary-$ARCH/Packages" -o "$TMP/Packages" || die "could not fetch Packages"
  echo "$want  $TMP/Packages" | sha256sum -c - >/dev/null 2>&1 \
    || die "package index hash does not match the signed Release — refusing to proceed"
  ok "package index verified against signed Release"
}

# --------------------------------------------- resolve the latest release ---
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --check: run only the signature/index verification and exit. Used by the CI
# "key canary" to detect if Anthropic ever rotates their primary signing key.
if [ "$CHECK_ONLY" -eq 1 ]; then
  fetch_verified_index
  ok "verification OK — live repo is signed by the pinned key and the index is intact"
  exit 0
fi

if [ -n "$LOCAL_DEB" ]; then
  [ -f "$LOCAL_DEB" ] || die "no such file: $LOCAL_DEB"
  DEB="$LOCAL_DEB"
  LATEST="$(basename "$LOCAL_DEB" | sed -n 's/.*_\([0-9.]*\)_.*/\1/p')"
  log "Using local package: $DEB (version ${LATEST:-unknown})"
  warn "a local --deb is NOT signature-verified (no signed index for an arbitrary file)"
else
  log "Querying official repo for the latest version…"
  fetch_verified_index
  # Flatten stanzas to: version<TAB>filename<TAB>sha256, then pick the newest.
  awk '
    /^Version:/  {v=$2}
    /^Filename:/ {f=$2}
    /^SHA256:/   {s=$2}
    /^[[:space:]]*$/ { if(v){print v"\t"f"\t"s}; v=f=s="" }
    END { if(v){print v"\t"f"\t"s} }
  ' "$TMP/Packages" | sort -t$'\t' -k1,1 -V | tail -1 > "$TMP/latest"
  LATEST="$(cut -f1 "$TMP/latest")"
  FILE="$(cut -f2 "$TMP/latest")"
  SHA="$(cut -f3 "$TMP/latest")"
  if [ -z "$LATEST" ] || [ -z "$FILE" ]; then die "could not parse latest version from repo"; fi
  ok "Latest available: $LATEST"
fi

# ------------------------------------------- compare with what's installed --
# The deb version lives only in the package's control metadata, not the
# payload (the payload's `version` file is Electron's, and package.json carries
# an unrelated internal number). So we record what we install in our own marker.
INSTALLED="$(cat "$APP/.deb-version" 2>/dev/null || echo "")"
if [ -n "$INSTALLED" ]; then
  log "Currently installed: $INSTALLED"
else
  log "No existing install found at $APP — fresh install."
fi

ICONSRC=""
if [ -z "$LOCAL_DEB" ] && [ -n "$INSTALLED" ] && [ "$FORCE" -eq 0 ] && version_le "$LATEST" "$INSTALLED"; then
  ok "Already up to date ($INSTALLED). Nothing to download."
  # still (re)apply integration + Arch adaptation below in case something's missing
else
  # ----------------------------------------------------------- download -----
  if [ -z "$LOCAL_DEB" ]; then
    DEB="$TMP/claude-desktop_${LATEST}_$ARCH.deb"
    log "Downloading $LATEST …"
    curl -fL --progress-bar "$REPO/$FILE" -o "$DEB" || die "download failed"
    if [ -n "${SHA:-}" ]; then
      log "Verifying SHA256…"
      if echo "$SHA  $DEB" | sha256sum -c - >/dev/null 2>&1; then
        if [ "$VERIFY" -eq 1 ]; then
          ok "package verified — SHA256 chains to Anthropic's signature"
        else
          ok "checksum verified (index was not signature-checked)"
        fi
      else
        die "checksum mismatch — refusing to install"
      fi
    fi
  fi

  # ------------------------------------------------------------ extract -----
  log "Extracting package…"
  ( cd "$TMP" && ar x "$DEB" )
  mkdir -p "$TMP/data"
  bsdtar -xf "$TMP"/data.tar.* -C "$TMP/data"
  SRC="$TMP/data/usr/lib/claude-desktop"
  [ -d "$SRC" ] || die "unexpected package layout ($SRC missing)"

  # --------------------------------------------- lay down payload in $APP ---
  log "Installing payload into $APP …"
  mkdir -p "$APP"
  # Replace payload but keep our own helper scripts + version marker.
  find "$APP" -mindepth 1 -maxdepth 1 \
    ! -name launch.sh ! -name uninstall.sh ! -name install.sh ! -name .deb-version \
    -exec rm -rf {} + 2>/dev/null || true
  cp -a "$SRC/." "$APP/"
  echo "$LATEST" > "$APP/.deb-version"
  ok "payload installed (version $LATEST, Electron $(cat "$APP/version" 2>/dev/null || echo '?'))"

  ICONSRC="$TMP/data/usr/share/icons/hicolor"
fi

# ------------------------------------------------- write helper scripts -----
# launch.sh (relocatable launcher)
cat > "$APP/launch.sh" <<'LAUNCH_EOF'
#!/usr/bin/env bash
# Launcher for the self-contained, isolated Claude Desktop install.
# Resolves its own location and execs the bundled Electron binary. The
# Chromium sandbox uses unprivileged user namespaces (Arch default), so no
# setuid root helper is needed. If user namespaces ever get disabled and the
# app refuses to start, uncomment the EXTRA_FLAGS line (disables the sandbox).
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
EXTRA_FLAGS=()
# EXTRA_FLAGS=(--no-sandbox)
exec "$HERE/claude-desktop" "${EXTRA_FLAGS[@]}" "$@"
LAUNCH_EOF
chmod +x "$APP/launch.sh"

# uninstall.sh
cat > "$APP/uninstall.sh" <<'UNINSTALL_EOF'
#!/usr/bin/env bash
# Uninstall the isolated Claude Desktop install.
#   ./uninstall.sh            # remove app + integration, keep settings
#   ./uninstall.sh --purge    # also delete ~/.config/Claude
#   ./uninstall.sh --yes      # don't prompt before deleting the app directory
set -euo pipefail
APP="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PURGE=0; ASSUME_YES=0
for arg in "$@"; do case "$arg" in
  --purge) PURGE=1 ;; --yes|-y) ASSUME_YES=1 ;;
  *) echo "Unknown option: $arg" >&2; exit 2 ;;
esac; done

echo "Removing desktop integration..."
rm -fv "$HOME/.local/bin/claude-desktop"
rm -fv "$HOME/.local/share/applications/claude-desktop.desktop"
rm -fv "$HOME/.local/share/mime/packages/com.anthropic.Claude.xml"
for sz in 16x16 32x32 48x48 128x128 256x256; do
  rm -fv "$HOME/.local/share/icons/hicolor/$sz/apps/claude-desktop.png"
done
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

if [ "$PURGE" -eq 1 ]; then
  echo "Purging user data..."; rm -rfv "$HOME/.config/Claude"
else
  echo "Keeping user data at ~/.config/Claude (use --purge to remove it)."
fi

# Root-owned Arch adaptation shims live outside this directory; remind only.
for shim in /usr/bin/virtiofsd /usr/share/OVMF/OVMF_CODE_4M.fd; do
  if [ -L "$shim" ] && readlink "$shim" | grep -q -e "Apps/claude-desktop" -e "edk2/x64"; then
    echo "NOTE: Arch shim remains (remove with: sudo rm $shim): $shim"
  fi
done

echo
echo "About to delete the application directory:"
echo "  $APP"
if [ "$ASSUME_YES" -ne 1 ]; then
  printf "Proceed? [y/N] "; read -r reply
  case "$reply" in y|Y|yes|YES) ;; *) echo "Left app directory in place."; exit 0 ;; esac
fi
cd "$HOME"; rm -rf "$APP"
echo "Done. Claude Desktop removed."
UNINSTALL_EOF
chmod +x "$APP/uninstall.sh"

# Drop a copy of this script next to the app for future updates. Works both
# when run from a file and when piped from curl (then $0 isn't a real file,
# so re-fetch from the canonical URL).
rm -f "$APP/update-claude-desktop.sh"   # migrate from the pre-repo name
DEST="$APP/install.sh"
# Resolve where we're running from. When piped (`curl | bash`) this is "bash",
# not a real script file, so only treat it as our source if it's an actual
# file whose first line is our shebang — otherwise fetch the canonical copy.
SELF="$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || true)"
if [ -n "$SELF" ] && [ -f "$SELF" ] && [ "$SELF" != "$DEST" ] \
   && IFS= read -r _l < "$SELF" && [ "$_l" = "#!/usr/bin/env bash" ]; then
  cp -f "$SELF" "$DEST"
elif [ ! -f "$DEST" ]; then
  curl -fsSL "$SELF_URL" -o "$DEST" 2>/dev/null || warn "could not fetch a local copy of install.sh"
fi
if [ -f "$DEST" ]; then chmod +x "$DEST"; fi

# -------------------------------------------- user-level desktop wiring -----
log "Wiring up menu entry, CLI command, icons and MIME types…"
mkdir -p "$HOME/.local/bin"
ln -sf "$APP/launch.sh" "$HOME/.local/bin/claude-desktop"

# icons: prefer the just-extracted set, else the single bundled icon
for sz in 16x16 32x32 48x48 128x128 256x256; do
  src="$ICONSRC/$sz/apps/claude-desktop.png"
  [ -f "$src" ] || src="$APP/resources/icon.png"
  dst="$HOME/.local/share/icons/hicolor/$sz/apps"
  mkdir -p "$dst"; if [ -f "$src" ]; then cp -f "$src" "$dst/claude-desktop.png"; fi
done

mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/claude-desktop.desktop" <<EOF
[Desktop Entry]
Name=Claude
Comment=Desktop application for Claude.ai
GenericName=AI Assistant
Keywords=AI;Chat;Assistant;Claude;Code;LLM;
Exec=$APP/launch.sh %U
Icon=claude-desktop
Type=Application
StartupNotify=true
StartupWMClass=com.anthropic.Claude
SingleMainWindow=true
Categories=Utility;Development;
MimeType=x-scheme-handler/claude;application/vnd.anthropic.mcpb;application/vnd.anthropic.skill;
Actions=NewChat;NewCode;

[Desktop Action NewChat]
Name=New Chat
Exec=$APP/launch.sh "claude://claude.ai/new?surface=chat&source=desktop_action"

[Desktop Action NewCode]
Name=New Claude Code Session
Exec=$APP/launch.sh "claude://code/new?source=desktop_action"
EOF

if [ -f "$APP/resources/linux-mime/com.anthropic.Claude.xml" ]; then
  mkdir -p "$HOME/.local/share/mime/packages"
  cp -f "$APP/resources/linux-mime/com.anthropic.Claude.xml" "$HOME/.local/share/mime/packages/"
fi
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
xdg-mime default claude-desktop.desktop x-scheme-handler/claude 2>/dev/null || true
ok "desktop integration ready"

# --------------------------------- Arch adaptation (Cowork): pkgs + shims ---
if [ "$DO_COWORK" -eq 1 ]; then
  log "Applying Arch adaptation for Cowork (QEMU micro-VM)…"
  if command -v pacman >/dev/null 2>&1; then
    missing_pkgs=()
    command -v qemu-system-x86_64 >/dev/null 2>&1 || missing_pkgs+=(qemu-system-x86)
    ls /usr/share/edk2/x64/OVMF_CODE.4m.fd >/dev/null 2>&1 || missing_pkgs+=(edk2-ovmf)
    if [ "${#missing_pkgs[@]}" -gt 0 ]; then
      log "Installing packages: ${missing_pkgs[*]}"
      as_root pacman -S --needed --noconfirm "${missing_pkgs[@]}" \
        || warn "pacman install failed — install ${missing_pkgs[*]} manually for Cowork"
    else
      ok "qemu-system-x86 and edk2-ovmf already present"
    fi
  else
    warn "pacman not found — skipping package install (Cowork needs qemu + OVMF)"
  fi

  for entry in "$(ovmf_shim)" "$(viofs_shim)"; do
    link="${entry%%|*}"; target="${entry##*|}"
    # -e follows symlinks, so a dangling link (target gone, e.g. app dir was
    # moved/reinstalled) reads as absent and gets recreated below.
    if [ -e "$link" ]; then
      ok "shim already present: $link"
    elif [ -e "$target" ]; then
      if [ -L "$link" ]; then log "Replacing stale shim: $link"; else log "Creating shim: $link -> $target"; fi
      as_root install -d "$(dirname "$link")"
      as_root ln -sf "$target" "$link"
      ok "shim created: $link"
    else
      warn "cannot create $link — target missing: $target"
    fi
  done
else
  log "Skipping Cowork Arch adaptation (--no-cowork)."
fi

echo
ok "Done. Installed version: $(cat "$APP/.deb-version" 2>/dev/null || echo '?')"
echo "    Launch from your app menu (\"Claude\") or run: claude-desktop"
# A new terminal picks up the CLI command automatically. An already-open shell
# caches its command table, so the just-created ~/.local/bin/claude-desktop
# symlink won't be found there until the table is refreshed — tell the user how.
case "${SHELL##*/}" in
  zsh)  rehint="rehash" ;;
  fish) rehint="(fish rescans automatically)" ;;
  *)    rehint="hash -r" ;;
esac
echo "    In your CURRENT shell, run '$rehint' first if the command isn't found yet."
