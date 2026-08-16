# DSH Launcher

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）的 Web GUI 装进鸿蒙原生应用的极简壳。
本项目完全由鸿蒙端DSH在matepad edge（api26.0.0）端全程生成，未做其他设备的适配验证，本仓库的操作流程与项目文件完全由dsh生成，安装及使用前请自行甄别。

- 零打包、零原生代码：一个 ArkTS 页面 + ArkWeb 组件，加载 dsh web 的前端
- 仅连接本机 `127.0.0.1:8080`（出于安全考虑，不支持远程地址配置）
- 自动探测后端：连不上时显示提示页 + 一键重试，恢复后自动进入
- 适配：HarmonyOS API 23+（`6.1.0(23)`），deviceTypes `2in1`

```
┌─────────────────────────┐        ┌──────────────────────────┐
│  DSH Launcher (HAP)     │  http  │  dsh web (backend)       │
│  仅连接本机后端         │        │  本机 127.0.0.1:8080     │
└─────────────────────────┘        └──────────────────────────┘
```

## 目录

- [从零开始（构建安装）](#从零开始构建安装)
- [部署 dsh 后端（前置步骤）](#部署-dsh-后端前置步骤)
- [使用](#使用)
- [常见问题](#常见问题)
- [开源说明](#开源说明)

## 从零开始（构建安装）

**前置条件**

| 项 | 要求 |
|---|---|
| 开发机 | Windows / macOS 均可，安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) |
| 华为账号 | 首次自动签名需要登录（免费调试证书） |
| 目标设备 | HarmonyOS API 23+ 的 2in1 / 平板 / 手机，**已部署 dsh web 服务**（见下节） |

**步骤**

1. 克隆本仓库，用 DevEco Studio 打开（File → Open）
2. 等待 Sync 完成（项目零外部依赖，不需要拉包）
3. （可选）修改 `AppScope/app.json5` 的 `bundleName` 为你自己的包名——
   改完 IDE 会自动为它生成匹配的调试签名材料
4. 连接设备 → Run / Build → 生成并安装 HAP

> **为什么不能直接分发成品 HAP**：鸿蒙调试签名 profile 绑定"包名 + 设备 UDID"，
> 在一台设备上签的 HAP 装不到另一台。给别人分发需走华为 AGC 的 release 签名
> （`build-profile.json5` 换成 AGC 下发的证书与 profile 即可）。

## 部署 dsh 后端（前置步骤）

本 App 只是窗口，**使用前必须先在本机部署好 dsh web 服务**（纯 Node 服务，
监听 `127.0.0.1:8080`）。完整的鸿蒙端部署方法（含踩坑修复、开机自启、
日常运维）已整理为两份文档，任选其一：

| 文档 | 适合谁 | 覆盖内容 |
|---|---|---|
| [dsh-harmonyos-install-guide.md](docs/dsh-harmonyos-install-guide.md) | 人类读者 | 完整安装步骤、每一步踩坑原因与修复、升级后重做清单、开机自启方案、日常命令 |
| [dsh-harmonyos-agent-install.md](docs/dsh-harmonyos-agent-install.md) | AI 编程助手 | 逐步可执行指令 + 每步验证命令 + 升级/重装后的完整重做清单 |

> 两份文档的操作方法提炼自 [dsh-harmonyos-deploy](https://atomgit.com/u010189254/dsh-harmonyos-deploy)
> （MIT License，Copyright (c) 2026 dsh-harmonyos-deploy contributors）。

**部署关键点速览**（详见文档）：

```bash
# 1. 安装 Node（HarmonyOS 版，如 harmonybrew）
# 2. 安装 dsh（官方包）
npm config set registry https://registry.npmmirror.com   # 国内镜像，可选
npm install -g @deepseek-ai/dsh
# 3. 打 HarmonyOS 兼容补丁（koffi 无 openharmony 构建，必打）
sh ~/.dsh/patches/reapply-koffi-patch.sh
# 4. 启动（幂等，已在跑会提示）
sh ~/.dsh/start-dsh-web.sh
# 5. 验证
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/   # 期望 200
```

开机自启（可选）：`sh ~/.dsh/autostart/install-autostart.sh`，详见人类版文档附录。

## 使用

1. 确保 dsh web 已在本机运行（见上节）
2. 打开 App，自动连接 `http://127.0.0.1:8080`
3. 连不上时显示提示页，点「重试」；确认 dsh web 已启动
4. 进入 DSH 全屏界面

## 常见问题

| 问题 | 解决 |
|---|---|
| `Metadata validation failed` | HAP 未正确签名。IDE 里 Build → Clean Project 后重新 Sync + Run；确认 build-profile.json5 的 signingConfigs 已由自动签名填充 |
| 提示无法连接 | 确认 dsh web 已在本机启动：`curl http://127.0.0.1:8080`；部署问题看上面的两份文档 |
| WebView 白屏但探针显示已连接 | 检查 dsh web 日志（`~/.dsh/dsh-web-8080.log`），确认前端资源完整 |

## 开源说明

- License：MIT（随仓库 LICENSE 文件）
- `docs/` 两份部署文档的部分内容提炼自 [dsh-harmonyos-deploy](https://atomgit.com/u010189254/dsh-harmonyos-deploy)（MIT），已按要求署名
- 本项目与华为 / DeepSeek 均无官方关联
- 后端使用请遵循 [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 仓库自身的许可
