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

任选一种方式获取代码。

### 方式一：git clone

```bash
git clone https://github.com/maxDNA/codex-input-unlock-macos.git
cd codex-input-unlock-macos
```

clone 会自动带上可执行位，可以直接进入「使用」。

### 方式二：从 Release 页面下载

到 [Releases](https://github.com/maxDNA/codex-input-unlock-macos/releases/latest) 页面下载最新压缩包，解压后进入目录。zip 不保存可执行位，需要先补一次：

```bash
chmod +x codex-input-unlock.sh 'Codex Input Unlock.command'
```

### 安装 Node.js

需要 Node.js 22+。未安装的话：

```bash
brew install node
```

### 非默认安装路径

如果 Codex Desktop 不在 `/Applications`，先设置环境变量：

```bash
export CODEX_APP_PATH='/path/to/ChatGPT.app'
```

这一步做在启动前即可，建议写进 `~/.zshrc` 省得每次设置。

---

## 使用

本工具只服务「登录官方账号 + 第三方 Provider」这一种场景；纯 API Key 方式（不登录官方账号）不会遇到这个门禁，无需本工具。请在 Codex Desktop 中登录你的 Codex 账号，并建议使用 ccswitch 或 magpie 等工具完成第三方 Provider 配置，本工具只解除门禁。本项目不会代您创建、修改或校验 Provider 配置。

如需手动检查配置，请先在 `~/.codex/config.toml` 中确保 Provider 配置中已经设置了 `requires_openai_auth = true`。

启动前请**完全退出**正在运行的 Codex Desktop（包括菜单栏图标），否则启动器会报错并拒绝启动。

下面两种启动方式任选其一。

### 方法一：命令行

```bash
cd codex-input-unlock-macos
./codex-input-unlock.sh launch
```

### 方法二：Finder 双击

在 Finder 中双击 `Codex Input Unlock.command`，窗口提示按回车关闭即表示启动完成。

### 验证与停止

```bash
./codex-input-unlock.sh verify
```

输出 `VERIFY: OK` 且 `gateStats.unlockCount > 0` 表示守护进程正常、断点已挂载，输入框已解除封锁。

```bash
./codex-input-unlock.sh stop
```

### 命令总览

```bash
./codex-input-unlock.sh launch    # 冷启动 Codex Desktop 并解锁输入框
./codex-input-unlock.sh verify    # 检查解锁状态
./codex-input-unlock.sh stop      # 停止 CDP 守护进程
./codex-input-unlock.sh diagnose  # 环境诊断（Node 版本、客户端路径、运行状态）
```

状态文件和日志保存在 `~/Library/Application Support/CodexInputUnlock/`。

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
