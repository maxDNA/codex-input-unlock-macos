# Codex Input Unlock (`codex-input-unlock-macos`)

English | [简体中文](README.md)

A macOS port of [1zero224/codex-input-unlock](https://github.com/1zero224/codex-input-unlock) (MIT). An **external runtime input unlocker** for the official Codex Desktop application on macOS (`/Applications/ChatGPT.app`).

When a user has configured a **third-party API provider, relay, or self-hosted gateway**, the official desktop client may still disable the composer and send button if the signed-in official account has exhausted its quota. Codex Input Unlock uses Chrome DevTools Protocol (CDP) to install a dynamic, non-pausing conditional breakpoint that **removes this local frontend input and send gate**.

> [!IMPORTANT]
> **Scope and disclaimer:**
> This project does **not and cannot** bypass, restore, or increase an OpenAI account's official quota. Its only purpose is to remove an unnecessary local frontend gate when you are already using **your own third-party API key and provider**.

---

## Features

- 🛡️ **No package modification:** Does not modify the app bundle, ASAR archive, or executable files. The official package and its signature remain untouched.
- 🔒 **No configuration management:** Never modifies, overwrites, or synchronizes `~/.codex/config.toml` or `auth.json`. You remain responsible for your own configuration.
- ⚡ **Non-pausing conditional breakpoint:** Uses a JavaScript comma expression such as `(quota = false, false)` to update the local variable while the breakpoint condition always evaluates to false, so the page never pauses.
- 🔄 **Automatic recovery after reload:** Watches the renderer lifecycle and reinstalls the breakpoint after a page reload.

---

## Install

```bash
git clone https://github.com/maxDNA/codex-input-unlock-macos.git
cd codex-input-unlock-macos
chmod +x codex-input-unlock.sh 'Codex Input Unlock.command'
```

If Node.js is not installed, install it with Homebrew using `brew install node`. The tool runs directly from the repository directory; no additional installation step is required.

If Codex Desktop is installed in a non-standard location, set the environment variable before launching:

```bash
export CODEX_APP_PATH='/path/to/ChatGPT.app'
```

## Usage

```bash
./codex-input-unlock.sh launch    # Cold-start Codex Desktop and unlock the composer
./codex-input-unlock.sh verify    # Check the unlock status
./codex-input-unlock.sh stop      # Stop the CDP supervisor
./codex-input-unlock.sh diagnose  # Environment diagnostics
```

You can also double-click `Codex Input Unlock.command` in Finder to launch.

State files and logs are saved under `~/Library/Application Support/CodexInputUnlock/`.

---

## How it works

```text
Shell controller (codex-input-unlock.sh)
  ├─ Checks Node.js 22+, the app bundle, and running instances
  ├─ Allocates a random TCP port and starts the Node.js CDP supervisor
  └─ Cold-starts Codex Desktop through `open --args` with debugging arguments
                        │
                        ▼
CDP supervisor (cdp-supervisor.mjs + quota-gate.cjs)
  ├─ Connects to the client renderer through CDP
  ├─ Locates the quota gate in the frontend JavaScript bundle
  ├─ Installs a conditional breakpoint: (quota = false, false)
  │    └─ Clears the local gate without pausing the renderer
  └─ Reinstalls the injection after a page reload
```

---

## Requirements

- **Operating system:** macOS (Apple Silicon / Intel)
- **Official client:** Codex Desktop, default path `/Applications/ChatGPT.app`, detected automatically by bundle ID `com.openai.codex`
- **Runtime dependencies:** Node.js 22+

---

## Quick start

### Configure your provider first

Before launching Codex Input Unlock, configure and verify your third-party provider in `~/.codex/config.toml`. This project does not create, modify, or validate provider configuration for you.

If you want to retain your official Codex account login while using the third-party provider, set the following option in the corresponding provider configuration:

```toml
requires_openai_auth = true
```

You must also sign in to your Codex account in Codex Desktop before using the unlocker. The third-party provider, `requires_openai_auth = true`, and the Codex login state must already be configured. Codex Input Unlock only removes the local input and send gate caused by the official quota state; it does not replace provider setup or account login.

### 1. Launch

> **Important:** Completely quit every running Codex Desktop process before launching, including the menu bar application. If the client is still running, the launcher will not terminate it. Instead, it displays an error with the matching process information.

```bash
./codex-input-unlock.sh launch
```

You can also double-click `Codex Input Unlock.command` in Finder.

### 2. Verify

```bash
./codex-input-unlock.sh verify
```

`VERIFY: OK` with `gateStats.unlockCount > 0` means that the supervisor is alive, CDP is connected, and the breakpoint has been installed.

### 3. Stop

```bash
./codex-input-unlock.sh stop
```

---

## Testing

```bash
node --check cdp-supervisor.mjs
node --check quota-gate.cjs
bash -n codex-input-unlock.sh
```

---

## Version adaptation

Codex releases re-minify and reshape the renderer bundle, so discovery uses **multiple anchors**:

1. **Semantic anchor:** a breakpoint inside the quota selector's `rate_limit?.allowed` guard treats quota data as available. It does not depend on composer component structure or minified names.
2. **Structural anchors:** locators for known composer submit-disabled chains (for example `composer-quota-consumer`) rewrite the gating variable to `false`.

At startup the supervisor arms every anchor found in the current bundle (up to four); any hit unlocks the composer. `breakpoints` and `gateStats.unlockCount` in `runtime-status-*.json` show which anchor actually fired. If a Codex update causes a startup timeout, the error carries `lastProbe` (quota atom count, presence of `submitDisabled`, per-locator matches). Run the self-test below before adding a rule:

```bash
node cdp-supervisor.mjs --self-test --gate quota-gate.cjs --bundle <extracted app-primary-*.js>
```

---

## Notes

1. **A cold start through the dedicated launcher is required.** Launching from the original official icon does not provide the CDP arguments.
2. **Only the local input gate is affected.** This tool does not fabricate server-side quota. Usage, authentication, and rate limits are controlled by your third-party provider.
3. **Unofficial project:** This project is independent and is not affiliated with OpenAI.

---

## License

[MIT](LICENSE)
