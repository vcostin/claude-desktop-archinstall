# Signing-key rotation runbook

What to do if Anthropic rotates the apt-repo signing key that `install.sh` pins.
This is rare (a full **primary** key change — routine subkey rotation is already
transparent, see [README › Security](README.md#security)).

## The golden rule

> **Never add a key just because it's the one the repo now presents.**
> Confirm the new fingerprint against an authoritative Anthropic source *first*.
> Pinning only protects you if the key you pin is provably genuine — blindly
> trusting whatever signed the repo today throws that away.

## Symptoms

Any of these means "a key you don't pin is now signing the repo":

- The **key-canary** workflow goes red.
- `install.sh` / `curl … | bash` fails with:
  `InRelease is not signed by a pinned Anthropic key (got 'XXXX…'; allowed: …)`
- `install.sh --check` fails the same way.

## Procedure

### 1. Capture the new fingerprint

```sh
install.sh --check
```
Note the `got '…'` fingerprint in the error. That's the primary key now signing
the repo. Don't trust it yet — verify it in step 3.

### 2. Obtain the new public key from an authoritative source

Prefer sources Anthropic controls over a keyserver:

- **The new official `.deb`** embeds the key in its `postinst`:
  ```sh
  mkdir -p /tmp/ctl && cd /tmp/ctl
  ar x /path/to/claude-desktop_<ver>_amd64.deb control.tar.*
  bsdtar -xf control.tar.* ./postinst 2>/dev/null || bsdtar -xf control.tar.* postinst
  sed -n '/BEGIN PGP PUBLIC KEY BLOCK/,/END PGP PUBLIC KEY BLOCK/p' postinst > new-key.asc
  ```
- **Anthropic's published archive keyring**
  (`…/claude-desktop-archive-keyring.asc`), and/or their security page /
  release announcement.

### 3. Verify the new key is genuine (the critical step)

```sh
gpg --show-keys --with-fingerprint new-key.asc
```
The printed fingerprint **must match**:
- the `got '…'` fingerprint from step 1, **and**
- the fingerprint Anthropic publishes out-of-band (security page / announcement).

If these don't all agree, **stop** — do not pin it.

### 4. Add it to the allowlist (coexist with the old key)

Edit `install.sh`:

1. Append the new fingerprint to `PINNED_FPS`, keeping the old one for now:
   ```sh
   PINNED_FPS="<OLD_FPR> <NEW_FPR>"
   ```
2. Paste the new armored key block **inside `anthropic_keys()`**, below the
   existing one. (`gpg` imports every block in the stream; verification accepts
   any allow-listed primary.)

Keeping both means installs work whether the repo is still on the old key or has
switched to the new one — no breakage during the changeover.

### 5. Test

```sh
install.sh --check        # should now print "repository signature valid"
```
Also run ShellCheck (`shellcheck install.sh`) — CI will too.

### 6. Commit and release

- Commit + push. The **key-canary** goes green again.
- Cut a patch release noting the new fingerprint (and that the old one is still
  accepted during transition).

### 7. Retire the old key (later)

Once Anthropic has fully cut over and you're confident nobody is still being
served the old signature:

1. Remove the old fingerprint from `PINNED_FPS`.
2. Remove its armored block from `anthropic_keys()`.
3. Commit + release.

## Quick reference

| Situation | Action |
| --- | --- |
| Canary red / install fails on signature | Start at step 1 |
| New fingerprint won't verify against Anthropic's published one | **Stop** — possible compromise/MITM; do not pin |
| Mid-rotation (both keys live) | Keep both in `PINNED_FPS` (step 4) |
| Old key fully retired upstream | Remove it (step 7) |

## Why this is safe

Adding a key is a deliberate, reviewed, source-controlled change — not something
the installer does automatically from the network. Until a human verifies and
pins the new key, installs **fail closed** (they refuse rather than trust an
unknown key). That's the trade-off that makes pinning worth it.
