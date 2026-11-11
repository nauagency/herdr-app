# Multi Agent Herdr: macOS development and packaging

This is the handoff runbook for an agent working on the Nauagency macOS app.
Read the root `AGENTS.md` first. Keep the repository's existing user changes,
and do not commit or push until the person has tested or explicitly asks.

## 1. Clone or update

```bash
mkdir -p "$HOME/0 Github"
cd "$HOME/0 Github"
git clone --recurse-submodules https://github.com/nauagency/herdr-app.git
cd herdr-app
git remote add upstream https://github.com/herdrdev/herdr-app.git 2>/dev/null || true
git fetch --all --tags --prune
git status --short
git pull --ff-only origin master
git submodule update --init --recursive
```

The repository is a monorepo: the Nauagency core is in `core/`. Do not clone a
second `multi-agent-herdr-core` repository beside the app.

Never discard a dirty worktree. Inspect it and preserve unrelated edits.

## 2. Native prerequisites

```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install zig bun jq create-dmg
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustup toolchain install 1.95.0
rustup default 1.95.0
rustup component add rustfmt
```

Required versions are Rust 1.95.0 and Zig 0.16.0. Verify before debugging:

```bash
rustc --version
zig version
bun --version
xcodebuild -version
```

## 3. Keep macOS aligned with Windows

Before editing, inspect the latest Windows behavior in `src/terminal.rs`,
`src/window.rs`, `defaults/mods/new-menu/`, and the Nauagency commits. Shared
Rust and mod code should remain shared. Put native browser/window/keychain code
behind one small `cfg(target_os = "macos")` module or function.

For every change:

1. Increment `0.1.13-nau.N` in both `Cargo.toml` and `Cargo.lock`.
2. Preserve the app name **Multi Agent Herdr**, bundle ID
   `com.nauagency.multi-agent-herdr`, and app home
   `~/.config/multi-agent-herdr`.
3. Verify each new agent tab gets isolated Codex/Claude/Antigravity credentials
   and session data. Do not copy tokens from the host profile.
4. Use the active/default macOS browser for OAuth. Never automate credentials.
5. Record any intentional Windows/macOS difference in this document.

The Windows-only PowerShell wrapper is
`defaults/mods/new-menu/run-agent-isolated.ps1`. macOS parity must use a native
shell wrapper rather than attempting to run PowerShell.

## 4. Build and test

```bash
cargo test --locked -- --test-threads=1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/test-control-plane.ps1
bun test scripts/files.test.ts scripts/machine-add.test.ts scripts/picker.test.ts \
  scripts/palette.test.ts scripts/agents.test.ts scripts/spaces.test.ts \
  scripts/worktree.test.ts
```

Install a local test build:

```bash
scripts/install-macos-nauagency
open "$HOME/Applications/Multi Agent Herdr.app"
```

Test creating two fresh tabs for every changed agent. Confirm they do not reuse
the first tab's login, OAuth opens the expected browser, copy/paste works, and
closing one tab does not stop another tab's agent.

## 5. Package and verify

```bash
scripts/package-nauagency
scripts/mac-dmg-nauagency
tar -tzf dist/multi-agent-herdr-macos-aarch64.tar.gz | head
codesign -dvv "$HOME/Applications/Multi Agent Herdr.app"
plutil -p "$HOME/Applications/Multi Agent Herdr.app/Contents/Info.plist"
hdiutil verify dist/Multi-Agent-Herdr.dmg
```

Without Apple secrets, `scripts/mac-sign` uses an ad-hoc signature suitable
only for local testing. A public package requires these GitHub secrets:

- `APPLE_CERTIFICATE_P12` (base64 Developer ID Application certificate)
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_API_KEY`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER` for notarization

Never print or commit their values.

## 6. Git and CI handoff

```bash
git diff --check
git status --short
git add <only-the-intended-files>
git commit -m "fix: describe the macos change"
git push origin master
```

The `multi-agent-herdr-packages` workflow builds native Windows and macOS
artifacts. Run it manually after a normal push. Pushing a `nau-v*` tag also
creates a GitHub Release containing the generated artifacts.
