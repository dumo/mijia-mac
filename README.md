# mijia-mac

用 Swift 写的 macOS 米家（Mi Home）客户端：菜单栏常驻 + 主窗口网格，能看设备、拨开关、执行场景。

它不是官方客户端，也不依赖任何第三方米家 SDK——整个米家 HTTP 协议（登录、RC4 加密、签名、
设备属性读写、场景执行）都在这份代码里用 Swift 原生实现了一遍。

---

## 当前状态

**自用开发中**，功能可用但不保证稳定。已实测跑通：扫码登录、多家庭 / 多房间、17 台设备的
属性读取、开关控制、场景执行、miot-spec 规格解析。

## 功能

| 模块 | 说明 |
|---|---|
| 登录 | 扫码登录（终端 ASCII + 二维码 PNG 双通道），凭据落盘本机，下次启动免扫码 |
| 主窗口 | 家庭 / 房间侧边栏 + 设备卡片网格；卡片顺序**首次拉取时固定**，之后只追加新设备，刷新不跳位 |
| 拖拽排序 | 手势重排（其余卡片实时让位），可一键恢复默认顺序 |
| 设备控制 | 卡片开关、详情页工作台（模块可增删 / 排序）、属性读写、动作执行 |
| 场景 | 手动场景列表与一键执行 |
| 状态栏 | 菜单内直接拨开关、跑场景；条目可勾选、可排序；支持单列 / 双列 |
| 传感器 | 温湿度计读数直接显示在卡片上，也可固定在菜单栏 |
| 小爱音箱 | 文本播报 |
| 刷新策略 | 启动 / 开窗口 / 开菜单时按 30 秒阈值节流刷新，手动刷新可强制 |

## 构建

要求 **macOS 26+ / Swift 6.2 / Xcode 27**（项目用了 SwiftUI 的 `.reorderable` 之外的
macOS 26 控件与 Swift 6 并发）。

```bash
# 库 + 命令行探针
swift build
swift test                      # 94 个测试

# 只读探针（登录后会列出家庭/设备，可扫描开关属性）
swift run mijia-probe --help
swift run mijia-probe --switchscan

# macOS App（工程由 project.yml 生成，不入库）
brew install xcodegen
cd Apps/MijiaMac && xcodegen && open MijiaMac.xcodeproj
```

## 工程结构

```
Sources/MijiaCore/        协议核心（库）：登录、加密签名、设备/场景/规格、属性读写
Sources/mijia-probe/      命令行探针，用于脱离 App 验证协议
Apps/MijiaMac/            macOS 应用：SwiftUI + AppKit（NSWindow 托管主窗口）
  project.yml             xcodegen 源，Xcode 工程是生成物
Tests/MijiaCoreTests/     单元测试（Swift Testing），含与参考实现逐字节对拍的黄金向量
Tools/gen_golden.py       生成加密层黄金测试向量
```

---

## 与 Do1e/mijia-api 的关系（重要）

本项目的协议知识来自对 **[Do1e/mijia-api](https://github.com/Do1e/mijia-api)**（Python，
GPL-3.0）所公开的米家 HTTP 协议事实的学习。

**必须说明清楚的是：**

- 本项目**没有复制其任何代码**，也没有把它作为依赖引入；
- `Tools/gen_golden.py` 是依据公开协议事实手写的**独立复现**，注释里明确写着
  「不 import mijiaAPI，避免把 GPL-3.0 代码带进本项目」；
- 所有 Swift 实现都是在本项目内独立完成的。

因此二者是**平行实现**关系，而非 fork 或派生。采用与上游相同的 GPL-3.0 是为免许可争议。

## 开源许可

**GNU General Public License v3.0**，完整文本见 [`LICENSE`](LICENSE)。

## 致谢

- **[Do1e/mijia-api](https://github.com/Do1e/mijia-api)**（GPL-3.0）—— 米家 HTTP 协议的
  公开整理与参考实现。本项目仅参考其协议事实（端点、参数、加密步骤），未复制代码。
- **[miot-spec.org](https://miot-spec.org/)**（小米官方设备规格实例库）—— 用于解析
  `siid` / `piid` 映射，规格结果在本地缓存。
- **[xcodegen](https://github.com/yonaskolb/XcodeGen)**（MIT）—— Xcode 工程由
  `Apps/MijiaMac/project.yml` 生成。
- Apple 系统框架：Foundation、SwiftUI、AppKit、CoreImage、Compression。

> 本项目**不含任何第三方运行时依赖**——`Package.swift` 里没有任何 `dependencies`。

---

## 隐私

登录凭据、设备列表、场景都是敏感数据，本项目的处理原则：

- 凭据 `auth.json` 只存在**本机** `~/.config/mijia-mac/auth.json`，**不在仓库内**，也从不上传；
- 应用设置存在 `~/Library/Application Support/mijia-mac/`，规格缓存存在
  `~/.config/mijia-mac/specs/`，同样不在仓库内；
- 仓库内**没有任何真实 token / cookie / 设备 ID**：测试夹具与代码注释里的示例全部是合成值
  （如 `100000001`、`FAKE_CUSERID_VALUE`、base64 的 `bytes(0..32)`）；
- `.gitignore` 额外兜底排除了 `auth.json`、`settings.json` 等文件名，防止有人把副本
  拷进项目目录后误提交；
- `.build/`（编译产物，二进制里会残留编译时的字面量）也在 `.gitignore` 中。

**如果你 fork 或二次开发，请先自查一遍有没有把本机数据带进来。**

## 免责声明

本项目是个人开发的学习 / 自用工具，**与小米公司无任何关联**。"米家"、"Mi Home"、
miot-spec 等为小米公司商标。

使用本项目即表示你了解：通过非官方接口访问米家服务，可能面临接口变更、账号风控等
情况，风险由使用者自行承担。
