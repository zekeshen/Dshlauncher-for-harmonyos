# DSH Launcher

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）的 Web GUI 装进鸿蒙原生应用的极简壳。

- 零打包、零原生代码：一个 ArkTS 页面 + ArkWeb 组件，加载 dsh web 的前端
- 仅连接本机 `127.0.0.1:8080`（出于安全考虑，不支持远程地址配置）
- 自动探测后端：连不上时显示提示页 + 一键重试，恢复后自动进入
- 适配：HarmonyOS API 23+（`6.1.0(23)`），deviceTypes `2in1`（也可改 phone/tablet）

```
┌─────────────────────────┐        ┌──────────────────────────┐
│  DSH Launcher (HAP)     │  http  │  dsh web (backend)       │
│  仅连接本机后端         │        │  本机 127.0.0.1:8080     │
└─────────────────────────┘        └──────────────────────────┘
```

## 目录

- [从零开始（构建安装）](#从零开始构建安装)
- [部署 dsh 后端](#部署-dsh-后端)
- [使用](#使用)
- [常见问题](#常见问题)
- [开源说明](#开源说明)

## 从零开始（构建安装）

**前置条件**

| 项 | 要求 |
|---|---|
| 开发机 | Windows / macOS 均可，安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) |
| 华为账号 | 首次自动签名需要登录（免费调试证书） |
| 目标设备 | HarmonyOS API 23+ 的 2in1 / 平板 / 手机 |

**步骤**

1. 克隆本仓库，用 DevEco Studio 打开（File → Open）
2. 等待 Sync 完成（项目零外部依赖，不需要拉包）
3. （可选）修改 `AppScope/app.json5` 的 `bundleName` 为你自己的包名——
   改完 IDE 会自动为它生成匹配的调试签名材料
4. 连接设备 → Run / Build → 生成并安装 HAP

> **为什么不能直接分发成品 HAP**：鸿蒙调试签名 profile 绑定"包名 + 设备 UDID"，
> 在一台设备上签的 HAP 装不到另一台。给别人分发需走华为 AGC 的 release 签名
> （`build-profile.json5` 换成 AGC 下发的证书与 profile 即可）。

## 部署 dsh 后端

dsh web 是纯 Node 服务，两种部署方式任选：

### 方式 A：本机模式（鸿蒙设备上跑后端）

```bash
# 1. 安装 Node（HarmonyOS 版，例如 harmonybrew）
# 2. 安装 dsh（官方包）
npm install -g @deepseek-ai/dsh
# 3. 配置模型 API key（dsh 首次启动引导，或直接编辑 ~/.dsh/settings.yaml）
# 4. 启动
dsh web --port 8080
```

开机自启（可选）：把启动命令写进系统自启项，或参考 `scripts/dsh-autostart.sh`（幂等：探活 → 原子锁 → setsid 常驻）。

### 方式 B：远程模式（后端跑在 PC / 服务器上）

> 注：本 App 出于安全考虑**仅支持连接本机后端**（`127.0.0.1:8080`）。
> 若确实需要远程后端，需自行修改 `entry/src/main/ets/pages/Index.ets` 顶部 `BACKEND_URL` 并重新构建。

## 使用

1. 打开 App，自动连接本机 `http://127.0.0.1:8080`
2. 连不上时显示提示页，点「重试」；确认 dsh web 已在本机启动
3. 进入 DSH 全屏界面

## 常见问题

| 问题 | 解决 |
|---|---|
| `Metadata validation failed` | HAP 未正确签名。IDE 里 Build → Clean Project 后重新 Sync + Run；确认 build-profile.json5 的 signingConfigs 已由自动签名填充 |
| 安装后桌面没有图标 | `entry/src/main/module.json5` 的 deviceTypes 改为 `["phone","tablet","2in1"]` 重构建 |
| 提示无法连接 | 确认 dsh web 已在本机启动：`curl http://127.0.0.1:8080` |
| WebView 白屏但探针显示已连接 | 检查 dsh web 日志，确认前端资源完整 |

## 开源说明

- License：MIT（随仓库 LICENSE 文件）
- 本项目与华为 / DeepSeek 均无官方关联
- 后端使用请遵循 [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 仓库自身的许可
