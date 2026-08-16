# DeepSeek Harness (dsh) HarmonyOS PC 安装指南

> 本文档总结了在 **HarmonyOS PC**(openharmony / aarch64)上安装 `@deepseek-ai/dsh`
> Web 服务的**完整正确经验**,包括每一步命令、每一个踩坑原因与修复方法。
> 面向人类读者,按顺序执行即可;另有一份《Agent 版》可交给 AI 助手自动执行。

---

> **内容来源与署名**：本文「附录」的操作方法与脚本说明提炼自
> [dsh-harmonyos-deploy](https://atomgit.com/u010189254/dsh-harmonyos-deploy)
> （MIT License，Copyright (c) 2026 dsh-harmonyos-deploy contributors）。
> 使用其中内容时请保留本署名与原始许可说明。

## 一、环境要求

| 项 | 要求 | 本机实测 |
|---|---|---|
| 系统 | HarmonyOS PC(OpenHarmony 系) | 鸿蒙 PC / API 26 |
| 架构 | aarch64(arm64) | 同左 |
| 运行时 | Node.js ≥ 20(harmonybrew 安装) | v26.x |
| 包管理 | npm(harmonybrew 自带) | 11.x |

**关键环境事实(决定了后面所有坑):**

1. 系统是 `openharmony`,npm 默认镜像源是 `https://repo.harmonyos.com/npm/`,
   **很多包(尤其 `@deepseek-ai/*`)在该源上不存在**,必须换源。
2. HarmonyOS 上的文件系统 **hmfs 禁止硬链接**(`link()` 返回 EPERM),且
   **强制文件权限 660、chmod 无效**。
3. koffi、sharp、node-pty 等原生模块**都没有 openharmony-arm64 的预编译二进制**。
4. Node 的 `NODE_OPTIONS` 不允许 `--expose-internals`(启动 HMR 需要它)。

---

## 二、安装步骤(一句话版)

```sh
# 1) 换镜像源 + 设置全局安装目录
npm config set registry https://registry.npmmirror.com
npm config set prefix "$HOME/.npm-global"

# 2) 安装 dsh(跳过所有原生模块的编译脚本,后面统一处理)
npm install --ignore-scripts -g @deepseek-ai/dsh

# 3) 打 koffi 兼容补丁(免编译,关键!)
sh ~/.dsh/patches/reapply-koffi-patch.sh

# 4) 启动
sh ~/.dsh/start-dsh-web.sh
# 访问 http://127.0.0.1:8080
```

> 为什么 `--ignore-scripts`:`@deepseek-ai/dsh-fs-local` 依赖原生模块 `koffi`,
> 其安装脚本会在没有 CMake/工具链的环境编译失败,导致整个安装中止。
> 而 koffi 只在 win32 专属包中被引用,打补丁后永远不会被加载,所以**不需要编译**。

---

## 三、完整安装步骤(含脚本部署)

### 3.1 部署辅助脚本(从 dsh-harmonyos-deploy 仓库获取)

参考仓库:[dsh-harmonyos-deploy](https://atomgit.com/u010189254/dsh-harmonyos-deploy)
(MIT License,Copyright (c) 2026 dsh-harmonyos-deploy contributors)。
克隆: `git clone https://atomgit.com/u010189254/dsh-harmonyos-deploy.git`

```sh
mkdir -p ~/.dsh/patches ~/.dsh/autostart ~/.dsh/config
# 脚本来源（仓库 scripts/ 目录，MIT 许可）：
#   scripts/start-dsh-web.sh           -> ~/.dsh/start-dsh-web.sh
#   scripts/reapply-koffi-patch.sh     -> ~/.dsh/patches/reapply-koffi-patch.sh
#   scripts/dsh-autostart.sh           -> ~/.dsh/autostart/dsh-autostart.sh
#   scripts/install-autostart.sh       -> ~/.dsh/autostart/install-autostart.sh
chmod +x ~/.dsh/start-dsh-web.sh ~/.dsh/patches/reapply-koffi-patch.sh \
         ~/.dsh/autostart/dsh-autostart.sh ~/.dsh/autostart/install-autostart.sh
```

### 3.2 安装 dsh

```sh
npm config set registry https://registry.npmmirror.com
npm config set prefix "$HOME/.npm-global"
npm install --ignore-scripts -g @deepseek-ai/dsh
~/.npm-global/bin/dsh --version   # 期望输出 0.1.0-rc.6
```

### 3.3 打 koffi 兼容补丁

```sh
sh ~/.dsh/patches/reapply-koffi-patch.sh
```

**补丁原理**:`dsh-sandbox-windows-acl`(win32 专属包)顶层 `import koffi`,
koffi 无 openharmony 构建、加载即失败。补丁把
`@deepseek-ai/dsh-sandbox-local/lib/index.js` 中对 windows-acl 的顶层 import
改为"仅 `process.platform === 'win32'` 时惰性 `await import()`"。
非 win32 平台永远不会用到它,所以 koffi 永远不会被加载。

### 3.4 打会话写入补丁(hmfs 禁硬链接)

`@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js` 创建会话文件时用
`link(tmp, finalPath)` 做原子发布,在 hmfs 上抛 `EPERM: operation not permitted`。

修改:`materializePosix()` 中 link 失败时回退到 `rename()`(同样原子,hmfs 支持):

```js
// 修改前
await link(tmp, finalPath);
// 修改后
try {
  await link(tmp, finalPath);
} catch (error) {
  if (error && ["EPERM", "ENOTSUP", "EOPNOTSUPP", "EACCES", "EXDEV"].includes(error.code)) {
    await rename(tmp, finalPath);
  } else {
    throw error;
  }
}
```

同时需要把 `rename` 加进 `node:fs/promises` 的 import 列表。

### 3.5 打凭据权限检查补丁(hmfs 强制 660)

`@deepseek-ai/dsh-credentials-local/lib/index.js` 的 `assertOwnerOnly()`
要求凭据文件 mode 为 600,但 hmfs **强制 660 且 chmod 无效**,检查永远失败。

修改:在 win32 分支旁追加 openharmony 豁免:

```js
if (process.platform === "win32") return;
if (process.platform === "openharmony") return;   // 新增
```

### 3.6 修复 sharp(attachment-local 依赖)

```sh
cd ~/.npm-global/lib/node_modules/@deepseek-ai/dsh
npm install @img/sharp-wasm32 --no-save --registry=https://registry.npmmirror.com
```

sharp 无 openharmony 二进制,官方推荐用 WebAssembly 运行时,免编译。

### 3.7 编译 node-pty(subprocess-local 依赖)

node-pty 无 openharmony prebuild,需源码编译(需要 make + clang):

```sh
brew install make
cd ~/.npm-global/lib/node_modules/@deepseek-ai/dsh/node_modules/node-pty
export CC=$HOME/.harmonybrew/bin/clang CXX=$HOME/.harmonybrew/bin/clang++
node $HOME/.harmonybrew/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js rebuild
```

### 3.8 修复 HMR(--expose-internals)

`cordis-plugin-hmr` 要求 Node 带 `--expose-internals` 启动,而
`NODE_OPTIONS` 被 Node 禁止传入该参数。解决办法:修改 `bin/dsh` 的 shebang:

```sh
# 修改 ~/.npm-global/bin/dsh 第一行
#!/usr/bin/env node
# 改为(内核直接支持解释器+单参数):
#!$HOME/.harmonybrew/bin/node --expose-internals
```

这样所有入口(手动启动 / start-dsh-web.sh / 自启脚本)都自动带上该参数。

---

## 四、启动 / 重启 / 停止

```sh
sh ~/.dsh/start-dsh-web.sh                      # 启动(幂等,已在跑会提示)
# 快速重启(先杀旧进程,因为启动脚本是幂等的):
kill $(ps -ef | grep "bin/dsh web" | grep -v grep | awk '{print $2}') 2>/dev/null; sleep 2; sh ~/.dsh/start-dsh-web.sh
# 访问 http://127.0.0.1:8080
tail -50 ~/.dsh/dsh-web-8080.log                # 看日志
```

> 建议把"快速重启"做成短命令 `dsh-web` 放到 `~/.local/bin/`,以后直接输入即可。

---

## 五、升级后必须重做的操作(dsh 重装会覆盖 node_modules)

| 序号 | 操作 | 命令/说明 |
|---|---|---|
| 1 | 重放 koffi 补丁 | `sh ~/.dsh/patches/reapply-koffi-patch.sh`(幂等) |
| 2 | 重打会话写入补丁 | 重复 3.4 节的 link→rename 修改 |
| 3 | 重打凭据权限补丁 | 重复 3.5 节的 openharmony 豁免 |
| 4 | 重装 sharp wasm | `cd ~/.npm-global/lib/node_modules/@deepseek-ai/dsh && npm install @img/sharp-wasm32 --no-save` |
| 5 | 重编 node-pty | 重复 3.7 节 node-gyp rebuild |
| 6 | 重改 bin/dsh shebang | 重复 3.8 节 `--expose-internals` |

> 提示:全部重做只需按 3.4~3.8 的顺序跑一遍,约 2 分钟。

---

## 六、踩坑速查表(按出现顺序)

| # | 现象 | 原因 | 解决 |
|---|------|------|------|
| 1 | `npm ERR 404` 装不到 `@deepseek-ai/dsh` | 默认源 repo.harmonyos.com 没有该包 | `npm config set registry https://registry.npmmirror.com` |
| 2 | 安装时 koffi 编译失败(缺 CMake) | koffi 无 openharmony 预编译,安装脚本要源码编译 | `--ignore-scripts` 安装 + koffi 补丁(无需编译) |
| 3 | 启动报 `Cannot find the native Koffi module` | windows-acl 顶层 import koffi 必崩 | `reapply-koffi-patch.sh` 改惰性加载 |
| 4 | `Could not load the "sharp" module` | sharp 无 openharmony-arm64 二进制 | 装 `@img/sharp-wasm32` |
| 5 | `Cannot find module ... pty.node` | node-pty 无 openharmony prebuild | `brew install make` + node-gyp rebuild |
| 6 | `--expose-internals is required for HMR` | HMR 插件需该参数,且 NODE_OPTIONS 被禁 | 改 `bin/dsh` shebang 为 node 绝对路径 + `--expose-internals` |
| 7 | `EPERM: operation not permitted, link ...` | hmfs 禁止硬链接 | session-persistence 的 link→rename 回退补丁 |
| 8 | `credentials-local: ... readable beyond its owner (mode 660)` | hmfs 强制 660 且 chmod 无效 | credentials-local 加 openharmony 豁免 |
| 9 | 沙箱不可用(命令无法执行) | HarmonyOS 不在 dsh 沙箱平台链 | 配置 `DSH_PERMISSION_MODE=danger-full-access`(见仓库 README) |
| 10 | dsh 临时文件散落在家目录根 | TMPDIR 默认指向 home | `export TMPDIR="$HOME/.dsh-tmp"`（启动脚本 start-dsh-web.sh 已内置） |
| 11 | 插件市场点"更新"没反应 / 静默 Already up to date | pnpm ≥10 的 minimumReleaseAge 冷静期 | `dsh plugin --profile web add <包>@<确切版本>` 绕过 latest 解析，或把版本加入 pnpm-workspace.yaml 的 minimumReleaseAgeExclude |

---

## 七、一句话经验总结

1. **换源**(npmmirror)+ **设 prefix**(~/.npm-global);
2. **`--ignore-scripts` 安装**,原生模块(koffi)不编译、只补丁;
3. **所有 node_modules 内的补丁升级后都会丢**,按第五节清单重做;
4. hmfs 的三个特殊性:**禁硬链接、强制 660、chmod 无效**,遇到权限类报错优先想到它们。


---

## 附录：开机自启配置与补充经验（提炼自 dsh-harmonyos-deploy）

> 本节内容提炼自 [dsh-harmonyos-deploy](https://atomgit.com/u010189254/dsh-harmonyos-deploy)
> （MIT License，Copyright (c) 2026 dsh-harmonyos-deploy contributors）。

### A. 开机自启方案（四层钩子，全部幂等）

鸿蒙的开机自启设置"只认软件（hap 应用）"，命令行脚本只能借道登录 shell 钩子：

| 层级 | 位置 | 触发时机 |
|---|---|---|
| 系统 profile | `/etc/profile` → `/data/service/el1/public/startup/profile`（sudo 写入） | 所有 sh 类登录 shell |
| zsh 环境 | `~/.zshenv` + `~/.zshrc` | zsh 每次启动 |
| bash | `~/.bashrc` + `~/.profile` | bash 登录/交互 |
| XDG | `~/.config/autostart/dsh-web.desktop` | 桌面环境（兼容备用，鸿蒙桌面实际不执行） |

核心脚本 `scripts/dsh-autostart.sh`：HTTP 探活（幂等）→ **mkdir 原子锁**（零外部依赖，带持锁者存活检测）→ setsid 常驻 → 60s 就绪等待。

安装：`sh ~/.dsh/autostart/install-autostart.sh`

系统级钩子（可选，需 sudo；鸿蒙 Toybox sudo 不支持 `-n`/`-i`，基础用法免密可用）：

```sh
# 注意：sudo 里 $HOME 是 root 的，下面的 <用户主目录> 必须换成字面路径
sudo sh -c 'grep -q "dsh web autostart" /data/service/el1/public/startup/profile || printf "\n# dsh web autostart (system profile hook)\n[ -x <用户主目录>/.dsh/autostart/dsh-autostart.sh ] && <用户主目录>/.dsh/autostart/dsh-autostart.sh >/dev/null 2>&1 &\n" >> /data/service/el1/public/startup/profile'
# 修改前先备份：cp /data/service/el1/public/startup/profile ~/.dsh/patches/startup-profile.bak
```

**实测局限（诚实说明）**：钩子本身全部生效（登录 shell 一执行，2~5 秒就绪）；
但鸿蒙 HiShell 开机自启打开的是 **Alpine/ttyAMA0 root 调试会话**（横幅显示
`Welcome to Alpine Linux of HiSH!`，环境其实是主系统、uid 仍是普通用户），且
**HiShell 开机后有 1~3 分钟延迟**，有时需手动点开一次 HiShell 才触发。
最可靠做法：重启后手动执行 `sh ~/.dsh/autostart/dsh-autostart.sh`。

### B. last-run.log 语义（排查自启问题必读）

`~/.dsh/autostart/last-run.log` 记录每次钩子执行去向：

| 记录 | 含义 | 下一步 |
|---|---|---|
| `already-running` | 探活通过，服务在跑 | 无需操作 |
| `locked-by-other` | 另一个实例正在启动 | 等几秒再查 8080 |
| `pid-alive, skip` | pid 文件显示已有实例 | 检查 pid 是否僵尸 |
| `launched pid=...` | 已启动 dsh 进程 | 等 60 秒内就绪 |
| `started OK` | 服务就绪 | 访问 8080 |
| `TIMEOUT` | 60 秒未就绪 | 看 dsh-web-8080.log 报错 |
| `dsh-bin-missing` | dsh 路径不存在 | 重装 dsh |

### C. 补充踩坑（原速查表未覆盖）

| 现象 | 原因 | 解决 |
|---|---|---|
| 自启脚本静默失败，日志全是 `locked-by-other, skip` | `flock` 只装在 harmonybrew，不在系统 PATH（/usr/bin:/bin），返回 127 被误判为"锁被占" | 改用 **mkdir 原子锁**（/bin/mkdir 在系统路径）+ 脚本固定 PATH + 每个分支写日志 |
| `df` 显示 /storage/Users 只有 12GB tmpfs | 覆盖挂载假象 | 实际数据在 hmfs 持久分区（~450GB），重启不丢数据 |
| `~/.hdc/` 调试日志爆炸（每小时 100MB） | hdc 默认开 debug | 定期清理旧日志 |
| `head -n -5` 不支持 / `whoami` 缺失 / `/tmp` 只读 | Toybox 精简工具集 | 用 `ls \| tail -5`、`cat /proc/self/status \| grep Uid`、用户目录替代 |
| 内存紧张 | WorkBuddy/浏览器等常驻占大头 | 跑大任务前关闭不用的常驻应用 |

### D. 日常命令速查

```sh
sh ~/.dsh/autostart/dsh-autostart.sh   # 幂等启动/自启
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/   # 验证 200
cat ~/.dsh/autostart/last-run.log      # 自启记录
tail -50 ~/.dsh/dsh-web-8080.log       # dsh 日志
sh ~/.dsh/patches/reapply-koffi-patch.sh  # dsh 升级后重放补丁
```
