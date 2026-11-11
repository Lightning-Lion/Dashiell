# Dashiell 本地编译指南（macOS / DevEco Studio）

本文记录在 macOS + DevEco Studio 下验证通过的依赖安装、环境配置和 HAP 编译流程。

## 1. 适用环境

- 执行位置：仓库根目录（下文命令均在此执行）
- DevEco Studio：`/Applications/DevEco-Studio.app`
- 项目设备类型：`wearable`（手表），不是 `phone`
- 构建模块及目标：`entry@default`
- 产品：`default`

下文 `/Applications/DevEco-Studio.app` 为默认安装位置；自定义安装路径请替换前缀。

## 2. 配置环境变量

在终端执行：

```bash
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:$PATH"
```

注意：

- 本机验证通过的 `DEVECO_SDK_HOME` 是 `Contents/sdk`。
- 设置为 `Contents/sdk/default` 或 `Contents/sdk/default/openharmony` 会报 `SDK component missing`。
- 使用 DevEco Studio 自带的 Node.js、Java 和 ohpm，避免使用到系统中不匹配的工具。
- 上述 `export` 仅对当前 shell 及其子进程生效，不会修改系统或 shell 配置文件。

## 3. 安装项目依赖

在项目根目录执行：

```bash
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install \
  --all \
  --registry https://ohpm.openharmony.cn/ohpm/ \
  --strict_ssl true
```

该命令会按 `oh-package.json5` 把全部依赖安装到 `oh_modules/`。

## 4. 停止旧的 Hvigor 守护进程

首次排障或修改 SDK、Java、Node 环境变量后，先停止旧守护进程，再重新构建：

```bash
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  --stop-daemon
```

## 5. 编译 HAP

确保已完成第 2 节环境配置，并在项目根目录执行：

```bash
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  --mode module \
  -p module=entry@default \
  -p product=default \
  -p requiredDeviceType=wearable \
  assembleHap \
  --analyze=normal \
  --parallel \
  --incremental \
  --daemon
```

成功输出示例：

```text
Finished :entry:default@PackageHap...
Finished :entry:default@SignHap...
Finished :entry:assembleHap...
BUILD SUCCESSFUL in 2 s 512 ms
```

上述耗时来自增量构建，不代表首次完整构建耗时。ArkTS 编译可能存在警告，但不阻止最终打包和签名。

## 6. 构建产物

签名包：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

未签名包：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

本文只覆盖编译、打包和签名成功，不包含设备安装或运行测试。换机后需确认项目签名配置引用的本地证书、Profile 和密钥文件可用；不要将私钥或密码写进仓库与文档（见根目录 `build-profile.json5` 的占位说明）。

## 7. 常见配置报错

| 报错 | 处理方式 |
| --- | --- |
| `00303217 Configuration Error` / `Invalid value of 'DEVECO_SDK_HOME'` | 显式设置 SDK 环境变量，并停止旧守护进程。 |
| `00303168 Configuration Error` / `SDK component missing` | 将 `DEVECO_SDK_HOME` 调整为 `/Applications/DevEco-Studio.app/Contents/sdk` 后通过 SDK 检查，无需修改项目 SDK 版本。 |
| `00303214 Configuration Error` / `Required device type:phone, current module device type:wearable` | 将命令参数改为 `-p requiredDeviceType=wearable`，保留项目设备配置。 |
| `00308018 Unknown Error` / `Unable to locate a Java Runtime` | 设置 `JAVA_HOME` 为 DevEco Studio 内置 JBR，并将 `$JAVA_HOME/bin` 加入 `PATH`，停止守护进程后重试。 |

若仍失败，可在编译命令后添加 `--stacktrace` 或 `--debug` 获取详细日志，并查看项目内的 `.hvigor/outputs/build-logs` 目录。
