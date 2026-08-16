# DSH HarmonyOS PC 部署指南(Agent 版)

> 本文件是给 **AI 编程助手(agent)** 的逐步执行指令,用于在 HarmonyOS PC
> (openharmony / aarch64)上安装并启动 `@deepseek-ai/dsh` Web 服务。
> 每一步都给出确切命令或精确的文件修改;agent 按顺序执行并在每步后验证。
> 人类读者请使用同目录下的《dsh-harmonyos-install-guide.md》。

---

## 0. 环境事实(先读,避免走弯路)

| 事实 | 含义 |
|---|---|
| `process.platform === "openharmony"`,`process.arch === "arm64"` | 不是标准 Linux,npm 默认源 `repo.harmonyos.com` 缺包 |
| 文件系统是 hmfs | **禁止硬链接**(`link()` 返回 EPERM);**强制文件权限 660 且 chmod 无效** |
| koffi / sharp / node-pty 无 openharmony-arm64 预编译 | 原生模块需特殊处理(koffi 用补丁免编译,sharp 用 wasm,node-pty 需编译) |
| `NODE_OPTIONS=--expose-internals` 会被 Node 拒绝 | HMR 需要该参数,只能改 bin 的 shebang |
| `~/.npm-global/bin` 可能不在当前 shell PATH | 一律用绝对路径 `$HOME/.npm-global/bin/dsh` |

**给 agent 的硬性规则(禁止项):**
- ❌ 不要试图编译 koffi(不需要装 CMake/Make 去编译它,补丁后它永不被加载)
- ❌ 不要用 `NODE_OPTIONS=--expose-internals`(会被 Node 拒绝)
- ❌ 不要用 `chmod 600` 期望修复凭据权限(hmfs 上 chmod 无效,要打豁免补丁)
- ✅ 每步修改后立刻验证;所有 node_modules 内的修改升级后会丢,最后统一列清单

---

## 1. 换源 + 设置全局安装目录

```sh
npm config set registry https://registry.npmmirror.com
npm config set prefix "$HOME/.npm-global"
npm config get registry        # 期望输出 https://registry.npmmirror.com/
```

---

## 2. 部署辅助脚本

创建目录并放置脚本(来源:GitHub 仓库 `dsh-harmonyos-deploy` 的 scripts/ 与 config/):

```sh
mkdir -p ~/.dsh/patches ~/.dsh/autostart ~/.dsh/config
# 依次下载到(用你习惯的方式,如 git clone 后复制,或 curl 对应 raw 地址):
#   scripts/start-dsh-web.sh       -> ~/.dsh/start-dsh-web.sh
#   scripts/reapply-koffi-patch.sh -> ~/.dsh/patches/reapply-koffi-patch.sh
#   scripts/dsh-autostart.sh       -> ~/.dsh/autostart/dsh-autostart.sh
#   scripts/install-autostart.sh   -> ~/.dsh/autostart/install-autostart.sh
chmod +x ~/.dsh/start-dsh-web.sh ~/.dsh/patches/reapply-koffi-patch.sh \
         ~/.dsh/autostart/dsh-autostart.sh ~/.dsh/autostart/install-autostart.sh
```

验证:`head -1 ~/.dsh/start-dsh-web.sh` 输出 `#!/bin/sh`。

---

## 3. 安装 dsh(跳过原生模块编译脚本)

```sh
npm install --ignore-scripts -g @deepseek-ai/dsh
$HOME/.npm-global/bin/dsh --version    # 期望 0.1.0-rc.6
```

> 若因网络失败,重跑一次即可;`--ignore-scripts` 必须保留。

---

## 4. 打 koffi 补丁(免编译,关键步骤)

```sh
sh ~/.dsh/patches/reapply-koffi-patch.sh
```

期望输出:`补丁已应用: .../dsh-sandbox-local/lib/index.js` 或 `补丁已生效,无需重放`。

**若脚本缺失或失败,手动执行**:修改
`$HOME/.npm-global/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js`,
把对 `@deepseek-ai/dsh-sandbox-windows-acl` 的顶层 import 替换为:

```js
let AclWriteGrant, assertTempRootOutsideWorkspace, tempWriteSid, workspaceWriteSid;
if (process.platform === "win32") {
	({ AclWriteGrant, assertTempRootOutsideWorkspace, tempWriteSid, workspaceWriteSid } = await import("@deepseek-ai/dsh-sandbox-windows-acl"));
}
```

验证:`grep -c 'process.platform === "win32"' <上述文件>` 输出 ≥ 1。

---

## 5. 打会话写入补丁(hmfs 禁硬链接)

文件:`$HOME/.npm-global/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js`

**5a.** import 行增加 `rename`:

```js
// 修改前
import { link, mkdir, mkdtemp, open, readFile, readdir, realpath, rm, stat, truncate } from "node:fs/promises";
// 修改后
import { link, mkdir, mkdtemp, open, readFile, readdir, realpath, rename, rm, stat, truncate } from "node:fs/promises";
```

**5b.** `materializePosix()` 内把发布逻辑改为 link 失败回退 rename:

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

验证:`node --check <文件>` 无报错(语法正确)。

---

## 6. 打凭据权限豁免补丁(hmfs 强制 660)

文件:`$HOME/.npm-global/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-credentials-local/lib/index.js`

在 `assertOwnerOnly()` 的 win32 分支后加一行:

```js
// 修改前
if (process.platform === "win32") return;
if ((mode & GROUP_OTHER_BITS) === 0) return;
// 修改后
if (process.platform === "win32") return;
if (process.platform === "openharmony") return;
if ((mode & GROUP_OTHER_BITS) === 0) return;
```

验证:`node --check <文件>` 无报错。

---

## 7. 修复 sharp(装 wasm 运行时)

```sh
cd "$HOME/.npm-global/lib/node_modules/@deepseek-ai/dsh"
npm install @img/sharp-wasm32 --no-save --registry=https://registry.npmmirror.com
```

验证(在该目录下):

```sh
node -e "require('sharp')(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==','base64')).metadata().then(m=>console.log('sharp OK:',m.format)).catch(e=>{console.error('FAIL',e.message);process.exit(1)})"
```

期望输出:`sharp OK: png`。

---

## 8. 编译 node-pty

```sh
brew install make
cd "$HOME/.npm-global/lib/node_modules/@deepseek-ai/dsh/node_modules/node-pty"
export CC="$HOME/.harmonybrew/bin/clang" CXX="$HOME/.harmonybrew/bin/clang++"
node "$HOME/.harmonybrew/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js" rebuild
```

验证:`ls build/Release/pty.node` 存在,且:

```sh
cd "$HOME/.npm-global/lib/node_modules/@deepseek-ai/dsh"
node -e "const p=require('node-pty').spawn('echo',['hello'],{}); p.onData(d=>process.stdout.write(d))"
```

期望输出:`hello`。

---

## 9. 修复 HMR(--expose-internals)

修改 `$HOME/.npm-global/bin/dsh` 的第一行 shebang:

```sh
# 修改前
#!/usr/bin/env node
# 修改后(用 node 绝对路径 + 参数,内核直接支持)
#!$HOME/.harmonybrew/bin/node --expose-internals
```

> node 绝对路径用 `which node` 确认;若路径不同请替换。

验证:`$HOME/.npm-global/bin/dsh --version` 输出 `0.1.0-rc.6` 且无 NODE_OPTIONS 报错。

---

## 10. 启动并验证

```sh
sh ~/.dsh/start-dsh-web.sh
```

期望输出:`已启动: http://127.0.0.1:8080/`

**完整验证(必须全部通过):**
1. `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/` → `200`
2. 触发真实会话创建(验证 EPERM 修复):
   ```sh
   timeout 40 "$HOME/.npm-global/bin/dsh" --profile headless "echo hello"
   find ~/.dsh/sessions -name "session.jsonl.zstd" | head -1   # 必须有输出
   ```
3. 日志无新报错:`grep -c "EPERM" ~/.dsh/dsh-web-8080.log` → `0`(或只含旧行)

---

## 11. 升级 / 重装后的完整重做清单

dsh 升级(`npm update` / `npm install`)会**覆盖 node_modules 和 bin/dsh**,以下
所有修改都会丢失。重装后按顺序重做(每步后验证):

```sh
# 1) 重放 koffi 补丁
sh ~/.dsh/patches/reapply-koffi-patch.sh

# 2) 重打会话写入补丁(第 5 节)
# 3) 重打凭据豁免补丁(第 6 节)
# 4) 重装 sharp wasm(第 7 节)
# 5) 重编 node-pty(第 8 节)
# 6) 重改 bin/dsh shebang(第 9 节)

# 7) 重启并做第 10 节完整验证
kill $(ps -ef | grep "bin/dsh web" | grep -v grep | awk '{print $2}') 2>/dev/null
sleep 2
sh ~/.dsh/start-dsh-web.sh
```

---

## 12. 故障排查(agent 遇到报错时对照)

| 报错关键词 | 定位 | 处理 |
|---|---|---|
| `404 Not Found`(npm) | 源缺包 | 确认 registry 为 npmmirror |
| `CMake does not seem to be available` / `koffi ... Failed to run build` | 安装脚本触发 koffi 编译 | 确认用了 `--ignore-scripts`;不要试图装 CMake 编译 |
| `Cannot find the native Koffi module` | koffi 补丁丢失 | 重跑 reapply-koffi-patch.sh |
| `Could not load the "sharp" module` | sharp wasm 未装 | 重装 `@img/sharp-wasm32` |
| `Cannot find module ... pty.node` | node-pty 未编译 | 重跑第 8 节 node-gyp rebuild |
| `--expose-internals is required` | shebang 被还原 | 重改 bin/dsh 第一行 |
| `EPERM: operation not permitted, link` | 会话补丁丢失 | 重打第 5 节补丁 |
| `readable beyond its owner (mode 660)` | 凭据豁免补丁丢失 | 重打第 6 节补丁 |
| 启动脚本提示"已在运行"但不重启 | 幂等保护 | 先 kill 旧进程再启动 |
| 沙箱不可用(命令不执行) | HarmonyOS 不在沙箱平台链 | 设置 `DSH_PERMISSION_MODE=danger-full-access` 后重启 |

---

## 13. 收尾

- 服务地址:`http://127.0.0.1:8080`
- 日志:`~/.dsh/dsh-web-8080.log`
- 会话数据:`~/.dsh/sessions/`
- 本文档对应的中文人类版:`dsh-harmonyos-install-guide.md`(同目录)

**交付完成标志:第 10 节完整验证 3 项全部通过。**
