# claude-desktop-archinstall

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

**Recommended — download, read, run.** It's a single ~400-line Bash file; please
read it before running (that's true of any install script):

```sh
curl -fsSLO https://raw.githubusercontent.com/vcostin/claude-desktop-archinstall/main/install.sh
less install.sh      # inspect it
bash install.sh
```

Or clone:

```sh
git clone https://github.com/vcostin/claude-desktop-archinstall
./claude-desktop-archinstall/install.sh
```

**One-liner** (convenient, but you're trusting this repo without reading it):

```sh
curl -fsSL https://raw.githubusercontent.com/vcostin/claude-desktop-archinstall/main/install.sh | bash
# pass flags through the pipe:
curl -fsSL .../install.sh | bash -s -- --force
```

Whichever you use, the script itself verifies the downloaded Claude Desktop
package against Anthropic's signing key before installing (see
[Security](#security)).

The same command **installs or updates** — run it again any time to pull the
latest release. A copy of the script is dropped at
`~/Apps/claude-desktop/install.sh` so you can update from there too.

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
./install.sh --deb FILE   # install from a local .deb instead of downloading
```

## Requirements

- Arch Linux (or an Arch-based distro with `pacman`)
- `curl`, `bsdtar` (`libarchive`), `binutils` (`ar`), `xz`, `coreutils`
  (`sha256sum`, `sort`) — all base/commonly installed
- `sudo` (only for the Cowork system steps)
- The Chromium sandbox uses unprivileged user namespaces, enabled by default
  on Arch — no setuid helper required.

## Updating

Re-run the script (`install.sh` or the copy in `~/Apps/claude-desktop/`). It
only downloads when a newer version is published. There is **no background
auto-update** — the Debian package's apt-repo registration is deliberately
skipped on Arch.

## Uninstalling

```sh
~/Apps/claude-desktop/uninstall.sh            # remove app + integration (keeps settings)
~/Apps/claude-desktop/uninstall.sh --purge    # also delete ~/.config/Claude
```

The uninstaller reminds you about the two root-owned Cowork symlinks (it can't
remove them without `sudo`).

## Security

The goal of this project is narrow: **distribution-compatibility installation of
the genuine app, nothing else.** No telemetry, no bundled binaries, no
third-party packager in the trust path.

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

**Verify the pinned key yourself.** The same key ships inside the official
`.deb`'s `postinst` and at Anthropic's published archive keyring, so you can
confirm the fingerprint independently.

**Flags.** `--insecure-skip-verify` disables the signature check (not
recommended). A local `--deb` is installed as-is and is *not* signature-checked,
since there's no signed index for an arbitrary file.

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

## License

[MIT](LICENSE) © Vadim Costin
