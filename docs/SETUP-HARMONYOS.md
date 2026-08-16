# 鸿蒙设备端启动装备说明（dsh web 后端部署）

在**另一台鸿蒙设备**上从零部署 DSH 后端的完整步骤。
本说明基于 HarmonyOS 7.0（API 26）/ MatePad Edge 验证，API 23+ 通用。

---

## 你需要准备

| 项 | 说明 |
|---|---|
| 鸿蒙设备 | 带 hishell 终端（开发者模式） |
| 网络 | 能访问 npmjs.org（装包用） |
| 模型 API Key | DeepSeek 或兼容 OpenAI 接口的密钥 |

---

## 第 1 步：安装 Node.js（二选一）

### 方式 A：Harmonybrew 安装（标准）

Harmonybrew 是 Homebrew 的鸿蒙移植版（仓库：`atomgit.com/Harmonybrew/brew`，
node 公式源：`atomgit.com/Harmonybrew/homebrew-core`）。

```sh
# 1. 按 Harmonybrew 仓库 README 安装 brew（本质同 Homebrew 安装流程）
# 2. 安装 node（会自动装 openharmony-arm64 构建）
brew install node

# 3. 验证
node -v    # 期望 v26.x
npm -v
```

### 方式 B：从现成设备移植（最快，适合给朋友）

在一台已经装好的设备上打包，直接拷过去：

```sh
# 源设备：
tar czf node-runtime.tar.gz -C ~/.harmonybrew Cellar/node bin/node bin/npm bin/npx bin/npx.js 2>/dev/null || \
tar czf node-runtime.tar.gz -C ~/.harmonybrew Cellar/node

# 目标设备：解压到相同路径
mkdir -p ~/.harmonybrew && tar xzf node-runtime.tar.gz -C ~/.harmonybrew
```

> 注意：node 是 musl 动态链接（依赖 `ld-musl-aarch64.so.1`，系统自带），
> 移植后无需额外安装运行时库。

---

## 第 2 步：安装 dsh

```sh
# 1. 确认 npm registry 是官方源（鸿蒙镜像只覆盖 @ohos 前缀）
npm config get registry        # 期望 https://registry.npmjs.org/
# 若被切到鸿蒙镜像：npm config set registry https://registry.npmjs.org/

# 2. 全局安装官方包
npm install -g @deepseek-ai/dsh

# 3. 把 npm 全局 bin 加进 PATH（写进 ~/.bashrc、~/.zshrc、~/.profile）
export PATH="$HOME/.npm-global/bin:$PATH"

# 4. 验证
dsh --version
dsh web --help
```

---

## 第 3 步：配置模型 API Key

**方式 A（推荐）**：启动后用界面引导配置

```sh
dsh web --port 8080
# 浏览器或 DshLauncher 打开 http://127.0.0.1:8080
# 首次进入按引导填写 API Key，会自动写入 ~/.dsh/.credentials.yaml
```

**方式 B（手动）**：直接写配置文件

```sh
mkdir -p ~/.dsh
cat > ~/.dsh/.credentials.yaml << 'CRED'
DEEPSEEK_API_KEY: sk-你的密钥
CRED
```

> dsh 首次运行会自动初始化 `~/.dsh` 与默认 web profile
> （内置 `@deepseek-ai/dsh-base` + `@deepseek-ai/dsh-web-app`，无需手工建）。

---

## 第 4 步：启动 dsh web

```sh
# 启动（App 固定连接本机 127.0.0.1:8080）
dsh web --port 8080

```

**常驻 + 自启**：仓库里的 `scripts/dsh-autostart.sh` 是幂等启动脚本
（探活 → 原子锁 → setsid 常驻 → 等待就绪），用法：

```sh
sh scripts/dsh-autostart.sh 8080          # 本机模式
```

> 说明：鸿蒙没有"用户脚本开机自启"机制（XDG autostart / rc.local / cron 均无效）。
> 重启设备后需要手动执行一次上面的命令（或开个终端跑一下）。

---

## 第 5 步：装 App 并连接

1. 构建/安装 DshLauncher HAP（见 README「从零开始」；调试签名只认登记设备）
2. 打开 App，自动连接本机 127.0.0.1:8080，进入 DSH 全屏界面

---

## 鸿蒙特有的坑（必看）

| 坑 | 现象 | 对策 |
|---|---|---|
| TMPDIR 指向 home | dsh 临时文件散落在家目录 | `export TMPDIR="$HOME/.dsh-tmp"`（脚本已内置） |
| npm registry 被劫持 | 装第三方包 404 | 检查 `~/.npmrc`，`registry` 改回 npmjs.org |
| 插件市场装包无反应 | pnpm 冷静期拦截 | `dsh plugin --profile web add <包>@<确切版本>` |
| 文件系统无硬链接/chmod 无效 | 工具链报 EPERM | 属平台限制，忽略或换复制方式 |
| 重启后后端消失 | App 显示无法连接 | 重跑 `scripts/dsh-autostart.sh` |

---

## 常见问题

- **App 显示"无法连接 DSH 后端"** → 先在本机 curl http://127.0.0.1:8080 验证；检查端口/地址/防火墙
- **装包时 dlopen 失败**（原生模块）→ 鸿蒙无 arm64 预编译，换有 wasm 后备的包或放弃该插件
- **想给别人免配置** → 见 README「开源说明」
