---
name: deb-to-arch
description: >-
  Adapt a Debian .deb application into a rootless, isolated Arch Linux install —
  payload in the user's home, XDG desktop integration, and signature
  verification against the vendor's key. Use when a vendor ships only a .deb,
  there's no trustworthy AUR package, and the user wants it running on Arch.
  Worked example included: Claude Desktop.
---

# .deb → rootless Arch install

A repeatable method for making a Debian `.deb` run natively on Arch Linux as a
**self-contained, rootless install** in the user's home directory, with full
desktop integration and cryptographic verification — no `dpkg`, no system-wide
package, no third-party repackager in the trust path.

## When to use this
- A vendor ships the app **only** as a `.deb` (Debian/Ubuntu).
- There's no AUR package, or the AUR package isn't trustworthy/maintained.
- The user wants it isolated in `~/` and/or updatable without root.

## When NOT to use it
- A maintained official Arch package or AUR package exists and is trusted → use that.
- The app isn't relocatable (hardcodes `/usr/...` paths it writes to) → may need a system install.
- You only need a quick throwaway → `debtap`/`alien` repackage faster (but produce a *system* pacman package, no rootless isolation, no vendor-signature verification, and won't do app-specific path fixes).

## Tools (all on a typical Arch box; none require dpkg)
`ar` (binutils), `bsdtar` (libarchive), `xz`, `sha256sum`/`sort`/`awk` (coreutils/gawk), `curl`, `gpg` (gnupg). Desktop integration uses `desktop-file-utils`, `shared-mime-info`, `gtk-update-icon-cache`, `xdg-utils`.

---

## The method

### 1. Inspect the package
```sh
ar x pkg.deb                        # → debian-binary, control.tar.*, data.tar.*
mkdir -p control data
bsdtar -xf control.tar.* -C control
bsdtar -xf data.tar.*    -C data
cat control/control                 # Depends, Architecture, Maintainer, Installed-Size
cat control/postinst 2>/dev/null    # what system integration it performs
find data -maxdepth 3 -type d       # payload layout (usr/lib/<app>, opt/..., usr/share)
```
Note the main payload dir (often `usr/lib/<app>` or `opt/<app>`), the launcher symlink in `usr/bin`, the `.desktop` file, and icons under `usr/share/icons`.

### 2. Find the REAL library dependencies
Don't trust `Depends:` literally — map it, but confirm with the linker:
```sh
ldd data/usr/lib/<app>/<binary> | grep -i 'not found'   # should be empty after deps installed
```
Common Debian→Arch name maps: `libgtk-3-0`→`gtk3`, `libnss3`→`nss`, `libnotify4`→`libnotify`, `libatspi2.0-0`→`at-spi2-core`, `libgbm1`/`libdrm2`→`mesa`/`libdrm`, `libsecret-1-0`→`libsecret`, `libasound2`→`alsa-lib`, `libappindicator3`→`libayatana-appindicator`. Install only what `ldd` actually reports missing.

### 3. Check relocatability (required for a rootless home install)
```sh
grep -aRIl "/usr/lib/<app>" data/usr/lib/<app> 2>/dev/null   # source files hardcoding the prefix?
grep -a -c  "/usr/lib/<app>" data/usr/lib/<app>/resources/app.asar  # electron apps: grep the asar
```
If nothing hardcodes the install prefix, the payload is **relocatable** and can live anywhere under `~/`.

### 4. Lay down the payload (rootless)
```sh
APP="$HOME/Apps/<app>"          # or ~/.local/opt/<app>
mkdir -p "$APP"
cp -a data/usr/lib/<app>/. "$APP"/
```
Write a **relocatable** launcher that resolves its own directory (survives moving the folder):
```sh
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
exec "$HERE/<binary>" "$@"
```

### 5. Desktop integration (user scope, XDG)
- CLI command: `ln -sf "$APP/launch.sh" ~/.local/bin/<app>`
- `.desktop` → `~/.local/share/applications/<app>.desktop`; rewrite `Exec=` to the **absolute** launcher path, keep `Actions`/`MimeType`/`StartupWMClass`.
- Icons → `~/.local/share/icons/hicolor/<size>/apps/<app>.png`.
- MIME defs (if any) → `~/.local/share/mime/packages/`.
- Refresh caches: `update-desktop-database`, `update-mime-database ~/.local/share/mime`, `gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor`.
- URL scheme: `xdg-mime default <app>.desktop x-scheme-handler/<scheme>`.

### 6. Sandbox / privilege (Electron/Chromium apps)
Arch enables unprivileged user namespaces by default, so the Chromium sandbox works **rootless** — no setuid `chrome-sandbox` needed. Check:
```sh
sysctl kernel.unprivileged_userns_clone   # expect 1 (or user.max_user_namespaces > 0)
```
Fallback only if userns is disabled: launch with `--no-sandbox` (less safe; document it).

### 7. Replay ONLY the safe parts of postinst
Read `control/postinst` and replicate the user-facing bits (MIME, desktop/icon caches, optional GNOME search provider). **Skip** everything Debian/Ubuntu-specific or system-wide: apt repo registration, AppArmor profiles, `dpkg` triggers, writes under `/etc`.

### 8. App-specific adaptation — the part that does NOT generalize
Some apps probe **Debian-only paths** for optional features. There's no tool for this; you investigate the app:
```sh
grep -aoE '/usr/(lib|libexec|share|bin)/[A-Za-z0-9_./-]+' "$APP"/resources/app.asar | sort -u
```
For each Debian path the app expects, create a compatibility **symlink** to the Arch equivalent (needs root), and install any Arch packages that provide the backing tools. Prefer bundled binaries the app already ships.

### 9. Trust — verify the download against the vendor's signing key
If the vendor publishes a **signed apt repo** (`InRelease`), don't settle for a plain checksum over TLS — verify authenticity by **pinning their key** and checking the full chain, failing **closed** on any mismatch:
```
pinned key ──▶ InRelease (gpg --verify) ──▶ Release ──▶ SHA256(Packages) ──▶ SHA256(.deb)
```
- Get the key from the `.deb`'s `postinst` (vendors often embed it) or the vendor's published keyring; **pin it in your script**, don't fetch it at runtime.
- Match the **primary** key fingerprint (GPG `VALIDSIG`'s last field) so routine subkey rotation doesn't break you.
- Add a scheduled CI "canary" that re-verifies the live repo against the pinned key, so a key rotation pages you before users hit failures.

### 10. Verify & definition of done
- `ldd` clean; smoke-launch (`<binary> --version` or a short run); optional features detected.
- Updates: re-fetch the newest version from the signed repo (parse `Packages`, pick newest via `sort -V`), verify, re-lay the payload. There is **no** apt auto-update on Arch — skipping the repo registration is intentional.

---

## Pitfalls (each of these actually bit during the Claude Desktop build)
- **Shell command hash:** a brand-new `~/.local/bin/<app>` isn't found in *already-open* shells until `rehash` (zsh) / `hash -r` (bash). New terminals are fine. Print a hint.
- **Dangling symlinks:** if the app dir is moved/reinstalled, shims pointing into it dangle. Detect with `-e` (follows the link) and recreate — don't treat `-L` alone as "present."
- **`curl | bash` and `$0`:** when piped, `$0` is `bash`, not a file; `readlink -f "$0"` can resolve to a real binary. Only copy the running file if it's genuinely your script (check the shebang), else re-fetch it.
- **CI ShellCheck is stricter than your local copy:** avoid `A && B || C` (SC2015); use explicit `if/then`. Pin or accept version drift.
- **Scope tool checks:** only require extraction tools (`ar`/`bsdtar`/`xz`) when actually unpacking, so verify-only/`--check` runs work on minimal environments.
- **Never assume parent dirs:** `mkdir -p` everything; a home without `~/Apps` must still work.
- **`--dir` rewires shared `~/.local` integration**, so it's not fully isolated for parallel installs (the CLI symlink/desktop entry are single-name).

---

## Worked example: Claude Desktop

Concrete values from adapting Anthropic's official `claude-desktop_amd64.deb`:

- **Payload:** `usr/lib/claude-desktop` — a self-contained Electron bundle (~580 MB, its own runtime). Nothing hardcodes `/usr/lib/claude-desktop`, so it's fully relocatable.
- **Deps:** all resolve on a typical Arch desktop; user namespaces are on by default, so the sandbox works rootless (no SUID helper).
- **Install dir:** `~/Apps/claude-desktop`; CLI at `~/.local/bin/claude-desktop`.
- **Integration:** `claude://` scheme handler, `.mcpb`/`.skill` MIME types, `StartupWMClass=com.anthropic.Claude`, New Chat / New Code desktop actions.
- **App-specific shims (Cowork — the QEMU micro-VM feature):** its detection in `resources/app.asar` probes Debian paths. Fixes:
  - `pacman -S --needed qemu-system-x86 edk2-ovmf`
  - `/usr/share/OVMF/OVMF_CODE_4M.fd` → `/usr/share/edk2/x64/OVMF_CODE.4m.fd`
  - `/usr/bin/virtiofsd` → `~/Apps/claude-desktop/resources/virtiofsd` (bundled; the app only auto-uses its bundled copy on Ubuntu 22.x)
  - needs KVM + `/dev/vhost-vsock` (standard on Arch). Detection symbols in the asar: `Lyn` (firmware list), `Ryn` (virtiofsd paths), `Jyn` (kvm/vsock).
  - **arm64 differs:** the app probes `/usr/share/AAVMF/AAVMF_CODE.fd` and `qemu-system-aarch64` (Arch pkgs `edk2-aarch64` + `qemu-system-aarch64`). The architecture is auto-detected from `uname -m`; firmware edk2 layouts vary, so resolve the target from candidate paths and warn (don't fail) if none match.
- **Trust:** repo `https://downloads.claude.ai/claude-desktop/apt/stable`; signing key *Anthropic Claude Code Release Signing*, fingerprint `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE` (pin it; it also ships in the `.deb`'s `postinst`).
- **Skipped from postinst:** apt-repo registration, AppArmor userns profile, GNOME search-provider wiring — all Debian/Ubuntu-specific.

The full implementation of this example is the `install.sh` in this repository.
