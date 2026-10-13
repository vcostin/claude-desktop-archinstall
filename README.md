# claude-desktop-archinstall

[![shellcheck](https://github.com/vcostin/claude-desktop-archinstall/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/vcostin/claude-desktop-archinstall/actions/workflows/shellcheck.yml)

Install [Claude Desktop](https://claude.ai) on **Arch Linux** from Anthropic's
official `.deb` — isolated in your home folder, rootless, with full desktop
integration and **Cowork** (the QEMU micro-VM feature) working.

Anthropic ships Claude Desktop for Linux as a `.deb` (Debian/Ubuntu). This
script makes that package behave like a native Arch install: it fetches the
latest official build, verifies it, lays it down as a self-contained Electron
app in `~/Apps/claude-desktop`, wires up the menu/CLI/MIME integration, and
applies the Arch-specific glue the Debian package can't (pacman dependencies
and the compatibility symlinks the app probes for at Debian paths).

> **Unofficial.** Not affiliated with or endorsed by Anthropic. The script
> does not redistribute Claude Desktop — it downloads the official package
> from `downloads.claude.ai` at runtime and **cryptographically verifies it
> against Anthropic's own signing key** (see [Security](#security)).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/vcostin/claude-desktop-archinstall/main/install.sh | bash
```

This **installs or updates** to the latest release — run it again any time. The
script verifies the download against Anthropic's signing key before installing
(see [Security](#security)), and drops a copy at `~/Apps/claude-desktop/install.sh`
so you can update from there too.

Pass flags by appending them after `--`:

```sh
curl -fsSL https://raw.githubusercontent.com/vcostin/claude-desktop-archinstall/main/install.sh | bash -s -- --force
```

**Prefer to read before running?** (Recommended for any install script.)
Download it, skim `install.sh`, then run it:

```sh
curl -fsSLO https://raw.githubusercontent.com/vcostin/claude-desktop-archinstall/main/install.sh && less install.sh && bash install.sh
```

Or clone the repo and run `./install.sh`.

## What it does

1. **Finds the latest version** from Anthropic's apt repo
   (`downloads.claude.ai/claude-desktop/apt/stable`) by parsing the `Packages`
   index and picking the newest with `sort -V`.
2. **Skips work if you're current** (tracked via a `.deb-version` marker),
   unless you pass `--force`.
3. **Downloads and verifies** the `.deb` against the repo's published SHA256.
4. **Installs the payload** into `~/Apps/claude-desktop` — a fully
   self-contained Electron bundle (no system Electron needed).
5. **Wires desktop integration**: a `claude-desktop` CLI command
   (`~/.local/bin`), an app-menu entry with *New Chat* / *New Code Session*
   actions, icons, MIME types, and the `claude://` URL scheme handler.
6. **Applies the Arch adaptation for Cowork**: installs `qemu-system-x86` and
   `edk2-ovmf` via `pacman` if missing, and creates two compatibility
   symlinks (see below). **`sudo` is only used for these system steps, and
   only when something is actually missing** — it prompts once.

### The Cowork symlinks

Claude's Cowork feature runs agent/code tasks inside a disposable QEMU
micro-VM. Its detection logic looks for tools at Debian paths, so on Arch two
symlinks are needed:

| Link (what the app looks for) | Target (Arch location) |
| --- | --- |
| `/usr/share/OVMF/OVMF_CODE_4M.fd` | `/usr/share/edk2/x64/OVMF_CODE.4m.fd` (`edk2-ovmf`) |
| `/usr/bin/virtiofsd` | `~/Apps/claude-desktop/resources/virtiofsd` (bundled) |

With those in place (plus KVM + `/dev/vhost-vsock`, standard on Arch), Cowork
reports as supported.

## Usage

```
./install.sh              # install or update to the latest
./install.sh --force      # reinstall even if already current
./install.sh --no-cowork  # skip the QEMU/virtiofsd Arch adaptation
./install.sh --dir PATH   # install dir (default ~/Apps/claude-desktop)
./install.sh --name ID    # install id for parallel installs (default: dir basename)
./install.sh --deb FILE   # install from a local .deb instead of downloading
./install.sh --check      # verify the repo signature only, then exit
```

### Parallel installs

All user-level integration is named after an **install id** (the `--dir`
basename, or `--name`), so you can run more than one build side by side:

```sh
# a second, independent install (e.g. a beta), with its own menu entry + command
./install.sh --dir ~/Apps/claude-beta --name claude-beta
```

That gives a `claude-beta` command, a "Claude (claude-beta)" menu entry, and its
own icon — without disturbing the default `claude-desktop` install. The default
install (id `claude-desktop`) is the **primary**: it alone owns the shared
`claude://` URL handler and file-type associations, so a secondary install never
hijacks them (or removes them when *it* is uninstalled).

A few things are genuinely shared and can't be isolated: the `claude://` handler
(only one default is possible), the Cowork system symlinks (`/usr/bin/virtiofsd`
etc. — use `--no-cowork` on secondaries, or accept last-writer-wins), and the
window grouping (both builds report the same `StartupWMClass`, so docks group
their windows together).

## Requirements

- Arch Linux (or an Arch-based distro with `pacman`)
- **amd64 (x86_64) or arm64 (aarch64)** — the architecture is auto-detected and
  the matching official build is fetched. Core install + signature verification
  are validated on both; on arm64 the Cowork *firmware* shim (AAVMF) is
  best-effort and warns rather than fails if the firmware package lays its files
  at an unexpected path.
- `curl`, `bsdtar` (`libarchive`), `binutils` (`ar`), `xz`, `coreutils`
  (`sha256sum`, `sort`), `gpg` (`gnupg`) — all base/commonly installed
- `sudo` (only for the Cowork system steps)
- The Chromium sandbox uses unprivileged user namespaces, enabled by default
  on Arch — no setuid helper required.

## Updating

Re-run the installer — it only downloads when a newer version is published:

```sh
~/Apps/claude-desktop/install.sh
```

The `curl … | bash` one-liner from [Install](#install) updates too. There is
**no background auto-update** — the Debian package's apt-repo registration is
deliberately skipped on Arch.

## Uninstalling

Remove the app and desktop integration (keeps your settings):

```sh
~/Apps/claude-desktop/uninstall.sh
```

Also delete your data at `~/.config/Claude`:

```sh
~/Apps/claude-desktop/uninstall.sh --purge
```

The uninstaller reminds you about the two root-owned Cowork symlinks (it can't
remove them without `sudo`).

## Security

The goal of this project is narrow: **distribution-compatibility installation of
the genuine app, nothing else.** No telemetry, no bundled binaries, no
third-party packager in the trust path.

**Verification is on by default.** Every normal install performs the check
below; there is no flag to enable. Disabling it requires an explicit
`--insecure-skip-verify`.

**What it verifies.** The installer pins Anthropic's apt-repo signing key
(*Claude Code Release Signing*, fingerprint
`31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`) *inside the script* and
checks the full chain before anything is installed:

```
pinned key ──▶ InRelease (GPG signature)
                  └─▶ Release ──▶ SHA256(Packages)
                                     └─▶ Packages ──▶ SHA256(.deb) ──▶ downloaded .deb
```

If the repository signature isn't from the pinned key, or any hash doesn't
match the signed index, the script **aborts before downloading or installing**.
This is stronger than a plain checksum: it verifies *authenticity* (it came
from Anthropic), not just integrity over TLS.

**Verify the pinned key yourself.** The key embedded in the script is a
*public* key (it can only verify signatures, never create them), and the same
key ships inside the official `.deb`'s `postinst` and Anthropic's published
archive keyring — so you can confirm it's genuine and public-only:

```sh
sed -n '/BEGIN PGP PUBLIC KEY BLOCK/,/END PGP PUBLIC KEY BLOCK/p' install.sh \
  | gpg --show-keys --with-fingerprint
```

Expected output — note `pub` (a public key; a secret would show `sec`) and the
fingerprint matching the one above:

```
pub   rsa4096 2026-03-30 [SCE]
      31DD DE24 DDFA B679 F42D  7BD2 BAA9 29FF 1A7E CACE
uid   Anthropic Claude Code Release Signing <security@anthropic.com>
```

**Flags.** `--insecure-skip-verify` disables the signature check (not
recommended). A local `--deb` is installed as-is and is *not* signature-checked,
since there's no signed index for an arbitrary file.

**Key rotation.** Verification matches Anthropic's *primary* key fingerprint, so
routine signing-subkey rotation needs no change here. A full primary-key change
is rare and would make installs fail *closed* (safe) until the pinned key is
updated — so a weekly CI canary (`install.sh --check`) re-verifies the live repo
and fails loudly if the pinned key ever stops matching. For a smooth changeover,
the pinned keys are an **allowlist** (`PINNED_FPS`): list the old and new primary
fingerprints (and both armored keys) together and installs keep working
throughout the rotation — verification accepts any pinned key. Step-by-step
procedure: [`KEY-ROTATION.md`](KEY-ROTATION.md).

**Still, read the script.** A `curl | bash` one-liner asks you to trust this
repo. Inspecting `install.sh` first (it's short and commented) is the honest way
to use it — especially given the 2026 wave of fake Claude Desktop installers.

## Troubleshooting

**`claude-desktop` not found right after installing, but works in a new terminal.**
Your shell caches the list of commands in each `PATH` directory. The installer
adds `~/.local/bin/claude-desktop` to an already-cached directory, so shells
that were already open don't see it yet. Refresh the current shell:

- zsh: `rehash` (or `source ~/.zshrc`)
- bash: `hash -r`

New terminals pick it up automatically. (If it's *also* missing in a brand-new
terminal, make sure `~/.local/bin` is on your `PATH`.)

## How it's laid out

```
~/Apps/claude-desktop/          # isolated, self-contained app
├── claude-desktop              # bundled Electron binary
├── resources/ …                # app.asar, helpers, virtiofsd, VM image
├── launch.sh                   # relocatable launcher
├── uninstall.sh                # uninstaller
├── install.sh                  # this script (for updates)
└── .deb-version                # installed deb version marker

~/.local/bin/claude-desktop                         # CLI command → launch.sh
~/.local/share/applications/claude-desktop.desktop  # menu entry
~/.local/share/icons/hicolor/*/apps/claude-desktop.png
```

## Adapting other `.deb` apps

The method behind this installer generalizes to any reasonably self-contained
`.deb`. It's written up as a reusable playbook (a Claude Code skill) at
[`skills/deb-to-arch/SKILL.md`](skills/deb-to-arch/SKILL.md) — the generic
steps (inspect → map deps → relocate → integrate → verify) plus the
app-specific gotchas, with Claude Desktop as the worked example. Drop it in
`~/.claude/skills/deb-to-arch/` to have Claude follow it on your next `.deb`.

## License

[MIT](LICENSE) © Vadim Costin
