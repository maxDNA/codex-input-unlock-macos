# Codex Input Unlock (`codex-input-unlock-macos`)

[English](README_EN.md) | 简体中文

macOS 移植版，源自 [1zero224/codex-input-unlock](https://github.com/1zero224/codex-input-unlock)（MIT），针对 macOS 官方 Codex Desktop（`/Applications/ChatGPT.app`）的**外部运行时输入解锁工具**。

当用户在客户端中配置了**第三方 API Provider**，且登录的官方账号没有额度时，官方客户端前端会强行将输入框与发送按钮置灰锁定。本项目通过 Chrome DevTools Protocol (CDP) 注入动态零暂停条件断点，**解除本地前端对输入框与发送动作的封锁**。

---

## 工作原理

```text
Shell 控制器 (codex-input-unlock.sh)
  ├─ 检查 Node.js 22+、应用存在、无运行中的实例
  ├─ 分配随机 TCP 端口，nohup 启动 Node.js CDP 守护进程
  └─ open --args 带调试参数冷启动 Codex Desktop
                        │
                        ▼
CDP 守护进程 (cdp-supervisor.mjs + quota-gate.cjs)
  ├─ 连接客户端 Renderer 调试端口
  ├─ 模式匹配定位前端 JS bundle 中的配额校验逻辑
  ├─ 安装条件断点：(quota = false, false)
  │    └─ 静默重置本地变量，条件恒为 false 永不挂起页面
  └─ 遇到页面刷新自动重新注入
```

---

## 环境要求

- **操作系统**：macOS（Apple Silicon / Intel）
- **官方客户端**：Codex Desktop，默认路径 `/Applications/ChatGPT.app`，通过 bundle ID `com.openai.codex` 自动检测
- **运行依赖**：Node.js 22+

---

## 安装

```bash
git clone https://github.com/maxDNA/codex-input-unlock-macos.git
cd codex-input-unlock-macos
chmod +x codex-input-unlock.sh 'Codex Input Unlock.command'
```

如果 Node.js 未安装，使用 Homebrew 执行 `brew install node`。工具直接从仓库目录运行，无需额外安装步骤。

如果 Codex Desktop 安装在非标准位置，设置环境变量后再启动：

```bash
export CODEX_APP_PATH='/path/to/ChatGPT.app'
```

## 使用

```bash
./codex-input-unlock.sh launch    # 冷启动 Codex Desktop 并解锁输入框
./codex-input-unlock.sh verify    # 检查解锁状态
./codex-input-unlock.sh stop      # 停止 CDP 守护进程
./codex-input-unlock.sh diagnose  # 环境诊断
```

也可以在 Finder 中双击 `Codex Input Unlock.command` 启动。

状态文件和日志保存在 `~/Library/Application Support/CodexInputUnlock/`。

---

## 快速上手

### 使用前配置

启动 Codex Input Unlock 前，请先在 `~/.codex/config.toml` 中配置并确认您的第三方 Provider 可以正常使用。本项目不会代您创建、修改或校验 Provider 配置。

如果您希望在使用第三方 Provider 的同时保留 Codex 官方账号的登录状态（例如继续使用依赖登录状态的功能），请在对应 Provider 配置中设置：

```toml
requires_openai_auth = true
```

同时请先在 Codex Desktop 中登录您的 Codex 账号。只有第三方 Provider、`requires_openai_auth = true` 和 Codex 登录状态均已准备好后，本工具才负责解除官方额度状态造成的本地输入与发送门禁；它不会替代 Provider 配置或账号登录。

### 1. 启动

> **注意**：启动前请**完全退出**正在运行的 Codex Desktop（包括菜单栏图标）。如果检测到客户端仍在运行，启动器不会关闭它，而是报错并保留进程信息。

```bash
./codex-input-unlock.sh launch
```

也可以在 Finder 中双击 `Codex Input Unlock.command`。

### 2. 验证状态

```bash
./codex-input-unlock.sh verify
```

输出 `VERIFY: OK` 且 `gateStats.unlockCount > 0` 表示守护进程正常、断点已挂载，输入框已解除封锁。

### 3. 停止

```bash
./codex-input-unlock.sh stop
```

---

## 测试

```bash
node --check cdp-supervisor.mjs
node --check quota-gate.cjs
bash -n codex-input-unlock.sh
```

---

## 版本适配

Codex 更新会重新压缩并调整前端 bundle 的结构，因此定位逻辑采用**多锚点**策略：

1. **语义锚点**：在配额 selector 内部 `rate_limit?.allowed` 的守卫语句处下断点，直接把配额数据视为可用。它与 composer 的组件结构和压缩变量名无关，只要该判定仍存在即可生效。
2. **结构锚点**：已知版本的 composer 提交禁用链定位器（如 `composer-quota-consumer`），在提交禁用变量的计算位置将其改写为 `false`。

启动时 supervisor 会同时挂载当前 bundle 中所有命中的锚点（最多 4 个），任一断点命中即可解锁；`runtime-status-*.json` 中的 `breakpoints` 与 `gateStats.unlockCount` 可用于确认实际生效的锚点。升级后若启动超时，错误信息会携带 `lastProbe`（quota atom 数量、`submitDisabled` 是否存在、各定位器命中情况）。补充规则前先运行：

```bash
node cdp-supervisor.mjs --self-test --gate quota-gate.cjs --bundle <解包后的 app-primary-*.js>
```

该命令会输出当前 bundle 命中的全部锚点与断点条件。

---

## 注意事项

1. **必须通过专属入口冷启动**：官方原版图标启动的进程不带 CDP 参数。
2. **仅解决本地输入框锁定**：本工具不伪造服务端 API 额度；第三方 API 的调用消耗、鉴权和限流由您配置的 Provider 自行处理。
3. **免责声明**：本项目为独立的非官方开源工具，与 OpenAI 无任何隶属关系。

---

## License

[MIT](LICENSE)


[LINUX DO](https://linux.do)
