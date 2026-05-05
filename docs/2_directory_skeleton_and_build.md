# EvilStore — 目录骨架、构建系统与开工蓝本（2 号文档）

> 版本：**v0.3（追加 §7.8 文件头规则，见末尾 §13.9）**
> 日期：2026-05-05
> 适用：v1（M0 → M5）；v2 helper 单独立 9 号文档
> 前置：1 号文档 v0.3 必读
>
> **本文档定位**：从空仓库 → 一份能 `xcodebuild` 通过、用 ldid 签名后能被 TrollStore 装上、桌面出现图标且能启动的"骨架 App"，再到每个模块的实现起点。读完本文档后，**直接进入编码阶段**。

---

## 目录

- [0. TL;DR — 第一天要做什么](#0-tldr--第一天要做什么)
- [1. 工具链选型 — Xcode 路线 vs theos 路线](#1-工具链选型--xcode-路线-vs-theos-路线)
- [2. 开发环境前置](#2-开发环境前置)
- [3. 仓库目录全景](#3-仓库目录全景)
- [4. 关键配置文件（可直接粘贴）](#4-关键配置文件可直接粘贴)
- [5. 模块 API 骨架（Swift protocol 层契约）](#5-模块-api-骨架swift-protocol-层契约)
- [6. 构建与安装脚本](#6-构建与安装脚本)
- [7. 编码规范与项目约定](#7-编码规范与项目约定)
- [8. 测试策略](#8-测试策略)
- [9. CI / CD（GitHub Actions）](#9-ci--cd-github-actions)
- [10. Milestone 任务拆解表（M0 → M5）](#10-milestone-任务拆解表m0--m5)
- [11. 首日 Checklist — 从空仓库到桌面图标](#11-首日-checklist--从空仓库到桌面图标)
- [12. 协作与版本约定](#12-协作与版本约定)

---

## 0. TL;DR — 第一天要做什么

按顺序：

1. 装好 Xcode 15+、ldid、coreutils（`brew install ldid coreutils`）。
2. 在仓库根目录用 Xcode "Create New Project → iOS → App" 建工程：
   - Product Name: `EvilStore`
   - Organization Identifier: `com.evil0ctal`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
   - Include Tests: **是**
3. 关闭 Xcode，删掉 Xcode 自动生成的目录里的 `Assets.xcassets` 等多余东西（保留 `EvilStore.xcodeproj` + `EvilStore/EvilStoreApp.swift` + `EvilStore/ContentView.swift`），按本文 §3 的目录树重新组织。
4. 拷贝本文 §4 的所有配置文件到对应路径（`Configuration/*.xcconfig`、`EvilStore/Resources/Info.plist`、`EvilStore/Resources/entitlements.plist`、`.gitignore`、`Scripts/build_tipa.sh`）。
5. 在 Xcode "Project → Info → Configurations" 把 Debug / Release 都指到对应 `.xcconfig`。
6. `chmod +x Scripts/*.sh && Scripts/build_tipa.sh`，应得到 `build/EvilStore.tipa`。
7. AirDrop / Filza 把 TIPA 推到测试设备，TrollStore 打开 → 安装。桌面应出现图标，启动后看到 `Hello, EvilStore` 文本。
8. 提交首个 commit：`build: skeleton boots under trollstore`（commit 风格见 §7.7）。
9. 进入 §10 M0.5 任务表。

如果第 6 步失败，**首选 §11 Checklist** 排查；不要边修边改架构。

---

## 1. 工具链选型 — Xcode 路线 vs theos 路线

> **重要决策（本文档采纳，覆盖 1 号文档 §3 的"theos + Makefile"提法）**：EvilStore 主 App 走 **Xcode 工程 + xcodebuild + 自写 TIPA 打包脚本** 路线。theos 仅在 v2 内嵌 helper（纯 ObjC + libarchive 小工具）阶段考虑。

### 1.1 选型对比

| 维度 | theos | Xcode + xcodebuild |
|---|---|---|
| Swift 支持成熟度 | 弱（`MyApp_SWIFT_FILES`，SPM 依赖手工） | 原生最佳 |
| SwiftUI 预览 | ❌ | ✅ |
| SPM 依赖（ZIPFoundation/Kingfisher） | 需 vendor 源码或 xcframework | `Package.swift` 直接拉 |
| ObjC↔Swift bridge | 手工写 bridging header | Xcode 自动生成 |
| ldid 签名集成 | 内置 | 自写 5 行 shell |
| TIPA 打包 | 内置 `package` target | 自写 ~30 行 shell |
| TrollStore-only app 社区实践 | 少（theos 多用于 tweak） | 多（Asspp、TrollStore 自身、各 GUI app） |
| CI 友好度 | 中（需要在 runner 装 theos） | 高（`xcodebuild` 是 macOS 自带） |

**结论**：主 App 用 Xcode；theos 在 9 号文档讨论 helper 时再回来。

### 1.2 Xcode 路线的"额外活儿"

相比 theos 自带的 `make package`，我们要自写：

- `Scripts/build_tipa.sh` — `xcodebuild archive` → 提取 `.app` → ldid 重签 → 打成 `Payload/` → zip 成 `.tipa`。约 40 行 bash，§6 给完整内容。
- `Scripts/bump_version.sh` — 读 `Configuration/Version.xcconfig`，递增并提交。约 20 行。

值得。换来的是 SwiftUI 预览、纯 SPM 依赖管理、Asspp 同款工程范式（出问题对照参考成本最低）。

---

## 2. 开发环境前置

### 2.1 macOS 主机要求

| 项 | 最低 | 推荐 |
|---|---|---|
| macOS | 13 Ventura | 14 Sonoma+ |
| Xcode | 15.0（含 iOS 17 SDK，能编 iOS 14 target） | 15.4+ |
| Command Line Tools | 与 Xcode 匹配 | 同左 |
| Homebrew | 任意 | 任意 |

```bash
# install all required tools in one go
brew install ldid coreutils jq xcbeautify
xcode-select --install   # only needed if Command Line Tools are missing
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

- `ldid` — 给二进制盖 fakesign（CoreTrust bypass 需要）。
- `coreutils` — 给我们 GNU `realpath`、`mktemp -d` 一致行为。
- `jq` — 部分脚本解析 plist 转 JSON 用。
- `xcbeautify` — 让 `xcodebuild` 输出可读，CI 也用。

### 2.2 测试设备要求

- iPhone / iPad 已装好 **TrollStore**（任一现役版本，1.4+ 推荐）。
- 系统 iOS **14.0 ~ 17.0**（含 16.7 RC）。
- 已登录 **副号** Apple ID（系统设置 → Apple ID）。**不要用主号**。
- USB / 同 Wi-Fi 与开发机通；推荐装 [Filza File Manager](https://github.com/opa334/Filza-TrollStore) 用于把 TIPA 拖进 TrollStore。

### 2.3 可选辅助

- **Proxyman / Charles** — M0.5 阶段抓 App Store 流量做协议比对（必须装系统 CA，且 App Store 启用 ATS pin，能抓到的字段有限，但 cookie 头能看）。
- **`class-dump-z` / Hopper / IDA** — 看 `accountsd` / `storeaccountd` 私有 framework 的 ObjC 接口签名。
- **theos**（仅 v2 helper 阶段需要）：`bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"`。v1 阶段**不要装**，避免误用。

---

## 3. 仓库目录全景

> 这份是最终目录树，M0 阶段先建好"占位但能编过"的最小子集（标 ✅ 的是 M0 必备；标 🔜 的是 M0.5+ 才动）。

```
EvilStore/                                       # 仓库根
├── README.md                                    ✅
├── LICENSE                                      ✅ (已有)
├── .gitignore                                   ✅
├── .editorconfig                                ✅
├── .swiftformat                                 ✅
├── .swiftlint.yml                               ✅
│
├── docs/                                        ✅ (已有)
│   ├── 1_project_overview_and_architecture.md
│   ├── 2_directory_skeleton_and_build.md        ← 当前
│   ├── 3_m05_stealth_poc_plan.md                🔜
│   ├── 4_appstore_protocol_reference.md         🔜
│   ├── 5_ipa_patching_and_install_pipeline.md   🔜
│   ├── 6_security_and_compliance.md             🔜
│   └── 9_v2_root_helper.md                      🔜 (v2)
│
├── Configuration/                               ✅
│   ├── Base.xcconfig                            ✅ 公共编译开关
│   ├── Debug.xcconfig                           ✅ Debug 覆盖
│   ├── Release.xcconfig                         ✅ Release 覆盖
│   ├── Version.xcconfig                         ✅ MARKETING_VERSION + CURRENT_PROJECT_VERSION 单一源
│   └── Developer.xcconfig.template              ✅ 个人签名占位（被 .gitignore）
│
├── EvilStore.xcodeproj/                         ✅ (Xcode 生成)
│
├── EvilStore/                                   ✅ 主 App target
│   ├── App/
│   │   ├── EvilStoreApp.swift                   ✅ @main
│   │   ├── AppDelegate.swift                    ✅ UIApplicationDelegateAdaptor — URL scheme 入口
│   │   ├── SceneDelegate.swift                  🔜
│   │   ├── Router.swift                         🔜 路由 / deeplink
│   │   └── Bootstrap.swift                      🔜 启动初始化（Logger / Importer 探测）
│   │
│   ├── UI/
│   │   ├── Root/
│   │   │   ├── RootView.swift                   ✅ 一个 TabView 占位
│   │   │   └── RootViewModel.swift              🔜
│   │   ├── Search/                              🔜
│   │   ├── Detail/                              🔜
│   │   ├── Downloads/                           🔜
│   │   ├── Library/                             🔜
│   │   ├── Settings/                            🔜
│   │   ├── Login/                               🔜  (manual fallback 模式专用)
│   │   └── Common/                              🔜
│   │
│   ├── Domain/
│   │   ├── Models/
│   │   │   ├── Account.swift                    🔜
│   │   │   ├── App.swift                        🔜
│   │   │   ├── VersionInfo.swift                🔜
│   │   │   ├── Sinf.swift                       🔜
│   │   │   ├── DownloadTask.swift               🔜
│   │   │   └── InstallResult.swift              🔜
│   │   ├── AccountService.swift                 🔜
│   │   ├── CatalogService.swift                 🔜
│   │   ├── VersionResolverService.swift         🔜
│   │   ├── DownloadService.swift                🔜
│   │   └── InstallService.swift                 🔜
│   │
│   ├── Core/
│   │   ├── AppStoreClient/
│   │   │   ├── AppStoreClient.swift             🔜 顶层 protocol
│   │   │   ├── AppStoreClientLive.swift         🔜 URLSession 实现
│   │   │   ├── Endpoints.swift                  🔜 单点收敛 endpoint
│   │   │   ├── Authenticate.swift               🔜  (manual fallback)
│   │   │   ├── Lookup.swift                     🔜
│   │   │   ├── Search.swift                     🔜
│   │   │   ├── Purchase.swift                   🔜
│   │   │   ├── ListVersions.swift               🔜
│   │   │   ├── Download.swift                   🔜
│   │   │   └── Bag.swift                        🔜
│   │   ├── HTTP/
│   │   │   ├── HTTPClient.swift                 🔜 URLSession 包装 + 节流
│   │   │   ├── PlistPayload.swift               🔜
│   │   │   └── CookieJar.swift                  🔜
│   │   ├── Plist/
│   │   │   └── PlistCoder.swift                 🔜
│   │   ├── Zip/
│   │   │   ├── IPAPatcher.swift                 🔜  (ZIPFoundation .update)
│   │   │   └── PartialZipReader.swift           🔜  (HTTP Range)
│   │   ├── Keychain/
│   │   │   └── KeychainVault.swift              🔜
│   │   ├── Device/
│   │   │   └── DeviceIdentifier.swift           🔜  (stealth 共享 + fallback random)
│   │   ├── SystemSession/                       🔜  (v0.3 新增)
│   │   │   ├── SystemSessionImporter.swift      🔜 protocol
│   │   │   ├── CompositeImporter.swift          🔜 链式策略
│   │   │   ├── AccountsdImporter.swift          🔜 路径 A
│   │   │   ├── AccountsdBridge.h                🔜 ObjC KVC 桥
│   │   │   ├── AccountsdBridge.m                🔜
│   │   │   ├── FileSystemImporter.swift         🔜 路径 B
│   │   │   ├── KeychainImporter.swift           🔜 路径 C（兜底）
│   │   │   └── BinaryCookiesParser.swift        🔜 .binarycookies → [Cookie]
│   │   └── TrollStore/
│   │       ├── TrollStoreBridge.swift           🔜 apple-magnifier:// 调用
│   │       └── TSErrorCatalog.swift             🔜 错误码 → 文案
│   │
│   ├── Util/
│   │   ├── Logger.swift                         🔜 swift-log 包装 + 敏感字段脱敏
│   │   ├── FileLayout.swift                     🔜 /var/mobile/Media/EvilStore/...
│   │   ├── Throttle.swift                       🔜 storefront 请求节流
│   │   └── HexCoding.swift                      🔜
│   │
│   ├── Resources/
│   │   ├── Info.plist                           ✅
│   │   ├── entitlements.plist                   ✅ M0 最小集；M0.5 后扩展
│   │   ├── Assets.xcassets                      ✅ AppIcon + AccentColor
│   │   └── Localizable.xcstrings                🔜  (zh-Hans + en)
│   │
│   └── EvilStore-Bridging-Header.h              🔜 (出现首个 ObjC 文件时)
│
├── EvilStoreTests/                              ✅ 单测
│   ├── AppStoreClientTests/                     🔜
│   ├── IPAPatcherTests/                         🔜
│   ├── PartialZipReaderTests/                   🔜
│   ├── BinaryCookiesParserTests/                🔜
│   ├── SystemSessionImporterTests/              🔜
│   └── Fixtures/
│       ├── login_2fa_required.plist             🔜
│       ├── list_versions_response.plist         🔜
│       ├── download_response.plist              🔜
│       ├── tiny_app.ipa                         🔜
│       └── sample.binarycookies                 🔜
│
├── EvilStoreUITests/                            🔜  (M5 之后再补)
│
├── ThirdParty/                                  🔜
│   ├── ApplePackage-reference/                  🔜 vendor 只读参考（git submodule，pin commit）
│   └── README.md                                🔜 列每个依赖的来源 + 许可
│
├── Scripts/                                     ✅
│   ├── build_tipa.sh                            ✅
│   ├── bump_version.sh                          ✅
│   ├── install_local.sh                         🔜  (sftp 推到设备)
│   ├── lint.sh                                  ✅
│   └── extract_storefront_ids.py                🔜
│
└── .github/                                     🔜
    └── workflows/
        ├── build.yml                            🔜
        └── lint.yml                             🔜
```

**M0 必须建好的最小子集**（不能少）：

```
.gitignore
.editorconfig
.swiftformat
.swiftlint.yml
docs/2_directory_skeleton_and_build.md          ← 本文
Configuration/{Base,Debug,Release,Version}.xcconfig
Configuration/Developer.xcconfig.template
EvilStore.xcodeproj
EvilStore/App/EvilStoreApp.swift
EvilStore/App/AppDelegate.swift
EvilStore/UI/Root/RootView.swift
EvilStore/Resources/{Info.plist, entitlements.plist, Assets.xcassets}
EvilStoreTests/EvilStoreTests.swift             ← 一个空测试
Scripts/build_tipa.sh
Scripts/bump_version.sh
Scripts/lint.sh
```

跑通 §11 checklist 后，再按 §10 milestone 表逐步把 🔜 文件填进去。

---

## 4. 关键配置文件（可直接粘贴）

> 这一节给的是**完整可粘贴**内容；按路径建文件即可。

### 4.1 `.gitignore`

```gitignore
# macOS
.DS_Store
*.swp

# Xcode
*.xcworkspace/xcuserdata/
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
DerivedData/
build/
*.xcarchive

# Configuration — 个人签名不进库
Configuration/Developer.xcconfig

# SPM
.swiftpm/
Package.resolved          # 团队作业建议提交；个人项目可忽略

# 输出物
*.ipa
*.tipa
*.dSYM.zip

# IDE
.idea/                    # JetBrains
.vscode/

# Python helper scripts
__pycache__/
*.pyc

# Logs
*.log
logs/

# Temp
tmp/
.tmp/
```

### 4.2 `.editorconfig`

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 4
insert_final_newline = true
trim_trailing_whitespace = true

[*.{md,yml,yaml,json}]
indent_size = 2

[Makefile]
indent_style = tab
```

### 4.3 `.swiftformat`

```ini
--swiftversion 5.7
--indent 4
--maxwidth 120
--wraparguments before-first
--wrapparameters before-first
--wrapcollections before-first
--commas inline
--trimwhitespace always
--allman false
--self remove
--header strip
```

### 4.4 `.swiftlint.yml`

```yaml
disabled_rules:
  - trailing_whitespace
  - todo
  - line_length

opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - sorted_imports
  - vertical_whitespace_closing_braces
  - vertical_whitespace_opening_braces

excluded:
  - ThirdParty
  - DerivedData
  - build
  - EvilStoreTests/Fixtures

identifier_name:
  min_length: 2
  excluded:
    - id
    - x
    - y
    - to

type_name:
  min_length: 3
  max_length: 60

function_body_length:
  warning: 60
  error: 120
```

### 4.5 `Configuration/Base.xcconfig`

```xcconfig
// EvilStore — 公共编译开关
// 所有 target 都先 #include 本文件，再被 Debug/Release 覆盖。

#include "Version.xcconfig"

// 平台
SDKROOT                              = iphoneos
IPHONEOS_DEPLOYMENT_TARGET           = 14.0
TARGETED_DEVICE_FAMILY               = 1,2          // iPhone + iPad
SUPPORTS_MACCATALYST                 = NO
SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO

// 标识
PRODUCT_BUNDLE_IDENTIFIER            = com.evil0ctal.evilstore
PRODUCT_NAME                         = EvilStore
DEVELOPMENT_LANGUAGE                 = en

// Swift
SWIFT_VERSION                        = 5.7
SWIFT_STRICT_CONCURRENCY             = minimal
SWIFT_TREAT_WARNINGS_AS_ERRORS       = NO
CLANG_ENABLE_MODULES                 = YES
DEFINES_MODULE                       = YES

// Optimization defaults — Debug/Release 各自再覆盖
GCC_OPTIMIZATION_LEVEL               = 0
SWIFT_OPTIMIZATION_LEVEL             = -Onone

// 资源
ASSETCATALOG_COMPILER_APPICON_NAME   = AppIcon
INFOPLIST_FILE                       = EvilStore/Resources/Info.plist
CODE_SIGN_ENTITLEMENTS               = EvilStore/Resources/entitlements.plist

// 关闭 ATS（私有 storefront 是 HTTPS，ATS 默认即可，但 PoC 阶段可能要抓包）
// 留给单文件 Info.plist 中显式声明 NSAllowsArbitraryLoads，不在这里全局放开。

// 签名（关键：让 Xcode 不要参与签名，由 build_tipa.sh 用 ldid 重签）
CODE_SIGN_STYLE                      = Manual
CODE_SIGN_IDENTITY                   = -                 // ldid placeholder
CODE_SIGNING_REQUIRED                = NO
CODE_SIGNING_ALLOWED                 = NO
PROVISIONING_PROFILE_SPECIFIER       =
DEVELOPMENT_TEAM                     =

// 个人开发签名覆盖（如需 Xcode debug 真机调试，自填 Developer.xcconfig 后 #include 它）
#include? "Developer.xcconfig"
```

### 4.6 `Configuration/Debug.xcconfig`

```xcconfig
#include "Base.xcconfig"

GCC_OPTIMIZATION_LEVEL               = 0
SWIFT_OPTIMIZATION_LEVEL             = -Onone
SWIFT_ACTIVE_COMPILATION_CONDITIONS  = DEBUG
ENABLE_TESTABILITY                   = YES
ONLY_ACTIVE_ARCH                     = YES
COPY_PHASE_STRIP                     = NO
GCC_PREPROCESSOR_DEFINITIONS         = DEBUG=1 $(inherited)
DEBUG_INFORMATION_FORMAT             = dwarf
```

### 4.7 `Configuration/Release.xcconfig`

```xcconfig
#include "Base.xcconfig"

GCC_OPTIMIZATION_LEVEL               = s
SWIFT_OPTIMIZATION_LEVEL             = -O
SWIFT_COMPILATION_MODE               = wholemodule
SWIFT_ACTIVE_COMPILATION_CONDITIONS  = RELEASE
ENABLE_TESTABILITY                   = NO
ONLY_ACTIVE_ARCH                     = NO
COPY_PHASE_STRIP                     = YES
DEBUG_INFORMATION_FORMAT             = dwarf-with-dsym
VALIDATE_PRODUCT                     = YES
```

### 4.8 `Configuration/Version.xcconfig`

> 单一版本号源；`Scripts/bump_version.sh` 改这里。

```xcconfig
MARKETING_VERSION         = 0.1.0
CURRENT_PROJECT_VERSION   = 1
```

### 4.9 `Configuration/Developer.xcconfig.template`

```xcconfig
// 复制为 Developer.xcconfig（被 .gitignore），仅在你想用 Xcode 真机 Debug 时填。
// 正常 TIPA 构建走 build_tipa.sh + ldid，无需此文件。
//
// DEVELOPMENT_TEAM        = ABCDE12345
// CODE_SIGN_STYLE         = Automatic
// CODE_SIGN_IDENTITY      = Apple Development
// CODE_SIGNING_REQUIRED   = YES
// CODE_SIGNING_ALLOWED    = YES
```

### 4.10 `EvilStore/Resources/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>EvilStore</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>14.0</string>

    <!-- 设备 / 方向 -->
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
    </array>

    <!-- 启动 Storyboard 改用 SwiftUI 启动屏 -->
    <key>UILaunchScreen</key>
    <dict/>

    <!-- 注册 evilstore:// 与挂钩 apple-magnifier 回调用的 host -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleURLName</key>
            <string>com.evil0ctal.evilstore.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>evilstore</string>
            </array>
        </dict>
    </array>

    <!-- App Store 私有 API 走 HTTPS，默认 ATS OK；M0.5 抓包阶段如果要 MITM，再覆盖此键 -->
    <!--
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
    -->

    <!-- 用户敏感行为说明（虽然我们走私有路径，但保险起见声明） -->
    <key>NSLocalNetworkUsageDescription</key>
    <string>EvilStore 不主动使用本地网络。</string>

    <!-- 文件分享：让"文件"App 能看到 EvilStore 的下载目录（可选） -->
    <key>UIFileSharingEnabled</key>
    <true/>
    <key>LSSupportsOpeningDocumentsInPlace</key>
    <true/>
</dict>
</plist>
```

### 4.11 `EvilStore/Resources/entitlements.plist` — M0 最小集

> ⚠️ **M0 阶段先用最小集**，能让 TrollStore 装上、能跑空 UI 即可。`com.apple.accounts.appleaccount.fullaccess` 等 stealth 模式所需 ent 在 M0.5 PoC 通过后再追加。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>application-identifier</key>
    <string>com.evil0ctal.evilstore</string>

    <key>platform-application</key>
    <true/>

    <key>com.apple.private.security.no-sandbox</key>
    <true/>

    <key>com.apple.security.exception.files.absolute-path.read-write</key>
    <array>
        <string>/</string>
    </array>

    <key>com.apple.private.security.storage.AppDataContainers</key>
    <true/>
</dict>
</plist>
```

### 4.12 `EvilStore/Resources/entitlements.plist` — M0.5 PoC 通过后扩展

> 仅作参考；**M0.5 完成前不要合入主 entitlements.plist**。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- M0 已有 -->
    <key>application-identifier</key>
    <string>com.evil0ctal.evilstore</string>
    <key>platform-application</key>
    <true/>
    <key>com.apple.private.security.no-sandbox</key>
    <true/>
    <key>com.apple.security.exception.files.absolute-path.read-write</key>
    <array><string>/</string></array>
    <key>com.apple.private.security.storage.AppDataContainers</key>
    <true/>

    <!-- M0.5 路径 A 验证通过后追加 -->
    <key>com.apple.accounts.appleaccount.fullaccess</key>
    <true/>
    <key>com.apple.private.accounts.bundleidspoofing</key>
    <true/>

    <!-- M0.5 路径 C 兜底（可选） -->
    <key>keychain-access-groups</key>
    <array>
        <string>*</string>
    </array>
    <key>com.apple.private.keychain.allowed-application-groups</key>
    <array>
        <string>com.apple.itunesstored</string>
    </array>
    <key>com.apple.private.keychain.unrestricted</key>
    <true/>

    <!-- M4 安装回环（v1 走 URL scheme 不需要；v2 helper 阶段补） -->
    <!--
    <key>com.apple.private.persona-mgmt</key><true/>
    <key>com.apple.private.MobileContainerManager.allowed</key><true/>
    <key>com.apple.private.MobileInstallationHelperService.allowed</key><true/>
    <key>com.apple.private.MobileInstallationHelperService.InstallDaemonOpsEnabled</key><true/>
    <key>com.apple.lsapplicationworkspace.rebuildappdatabases</key><true/>
    -->
</dict>
</plist>
```

### 4.13 `EvilStore/App/EvilStoreApp.swift` — M0 占位

```swift
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

@main
struct EvilStoreApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
```

### 4.14 `EvilStore/App/AppDelegate.swift` — M0 占位

```swift
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // smoke log so we know entitlements didn't reject the process
        NSLog("[EvilStore] launched. bundle=%@", Bundle.main.bundleIdentifier ?? "?")
        return true
    }

    // URL scheme entry; Router takes over after M1
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        NSLog("[EvilStore] open url: %@", url.absoluteString)
        return true
    }
}
```

### 4.15 `EvilStore/UI/Root/RootView.swift` — M0 占位

```swift
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            placeholder("Search")
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            placeholder("Downloads")
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            placeholder("Library")
                .tabItem { Label("Library", systemImage: "square.stack") }
            placeholder("Settings")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }

    private func placeholder(_ title: String) -> some View {
        NavigationView {
            VStack(spacing: 16) {
                Image(systemName: "hammer")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Hello, EvilStore")
                    .font(.title2.bold())
                Text("\(title) — coming soon")
                    .foregroundColor(.secondary)
            }
            .navigationTitle(title)
        }
    }
}

#if DEBUG
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .preferredColorScheme(.dark)
    }
}
#endif
```

### 4.16 `EvilStoreTests/EvilStoreTests.swift` — M0 占位

```swift
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import XCTest
@testable import EvilStore

final class EvilStoreSmokeTests: XCTestCase {
    func test_bundleIdentifier_isExpected() {
        // runs in test host; Bundle.main is the test runner — placeholder only
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
```

---

## 5. 模块 API 骨架（Swift protocol 层契约）

> 这一节把 1 号文档 §2.2 的模块表落成**可粘贴的 Swift 类型签名**。每个文件先建好 protocol + 主类型 + `Live` 占位实现（只 throw `unimplemented()`），具体逻辑按 §10 milestone 节奏填。
>
> 共用 utility：

```swift
// EvilStore/Util/Unimplemented.swift
struct Unimplemented: Error, CustomStringConvertible {
    let symbol: String
    var description: String { "unimplemented: \(symbol)" }
}
@inlinable
func unimplemented(_ symbol: String = #function) -> Never {
    fatalError("unimplemented: \(symbol)")
}
@inlinable
func unimplementedThrowing(_ symbol: String = #function) throws -> Never {
    throw Unimplemented(symbol: symbol)
}
```

> All Swift / ObjC / shell snippets below already follow §7.7. If you copy any line, keep its comment style; do not paraphrase into longer prose.
>
> **§5 snippets omit the SPDX file header for brevity.** When you create the actual file, prepend the two-line header per §7.8 before the first `import` / `#import` / `#include`.

### 5.1 `Domain/Models/Account.swift`

```swift
import Foundation

struct Account: Equatable, Codable {
    enum Source: String, Codable { case systemBorrowed, manual }

    var source: Source
    var email: String
    var firstName: String
    var lastName: String
    var directoryServicesIdentifier: String      // DSID
    var passwordToken: String?
    var storefront: String                       // e.g. "143441"
    var pod: String?
    var guid: String                             // 12 hex
    var cookies: [HTTPCookieBox]
    /// only persisted for .manual; .systemBorrowed always nil
    var encryptedPassword: Data?
}

/// HTTPCookie is not Codable; wrap it
struct HTTPCookieBox: Equatable, Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
}
```

### 5.2 `Domain/Models/App.swift`

```swift
import Foundation

struct App: Equatable, Codable, Identifiable {
    let id: Int64                    // salableAdamId / Apple's trackId
    let bundleID: String
    let name: String
    let version: String              // current marketing version on the store
    let storefront: String
    let artworkURL: URL?
    let primaryGenre: String?
    let formattedPrice: String       // "Free" / "$1.99"
}

struct VersionInfo: Equatable, Codable, Identifiable {
    var id: String { externalIdentifier }
    let externalIdentifier: String   // softwareVersionExternalIdentifier, e.g. "831776527"
    let displayVersion: String?      // resolved by PartialZipReader.peek
    let releaseDate: Date?
    let resolvedAt: Date             // when we last fetched; drives cache invalidation
}

struct Sinf: Equatable, Codable {
    let id: Int64
    let data: Data
}
```

### 5.3 `Core/AppStoreClient/AppStoreClient.swift`

```swift
import Foundation

protocol AppStoreClient {
    func bag() async throws -> StorefrontBag
    func search(term: String, country: String, limit: Int) async throws -> [App]
    func lookup(bundleID: String, country: String) async throws -> App
    func authenticate(email: String, password: String, code: String?) async throws -> Account
    func purchase(account: Account, app: App) async throws -> Account     // returns account with refreshed cookies
    func listVersions(account: inout Account, app: App) async throws -> [String]   // externalIdentifiers
    func download(
        account: inout Account,
        app: App,
        externalVersionID: String?,
        progress: @Sendable (Progress) -> Void
    ) async throws -> DownloadOutput
}

struct StorefrontBag: Codable {
    let authEndpoint: URL
    // additional fields parsed by Bag.swift
}

struct DownloadOutput {
    let url: URL                     // local .ipa path
    let sinfs: [Sinf]
    let metadata: [String: Any]      // injected as iTunesMetadata.plist
}
```

`Endpoints.swift` 单点收敛（**唯一可能因 Apple 改协议而需要热修的文件**）：

```swift
enum Endpoints {
    static let bag       = URL(string: "https://init.itunes.apple.com/bag.xml")!
    static let iTunes    = URL(string: "https://itunes.apple.com")!
    static let buyHost   = "buy.itunes.apple.com"
    static let pathPurchase = "/WebObjects/MZFinance.woa/wa/buyProduct"
    static let pathDownload = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"

    static func storeHost(pod: String?) -> String {
        pod.map { "p\($0)-\(buyHost)" } ?? buyHost
    }

    static var userAgent: String {
        // verified via ApplePackage; bump here when Apple changes the protocol
        "Configurator/2.0 (Macintosh; OS X 11.0.0; 16G29) AppleWebKit/2603.3.8"
    }
}
```

### 5.4 `Core/SystemSession/SystemSessionImporter.swift`

```swift
import Foundation

enum SystemSessionError: Error, Equatable {
    case notLoggedIn
    case entitlementDenied(String)
    case fileFormatChanged(path: String)
    case tokenDecryptionFailed
    case allPathsFailed([String])
}

protocol SystemSessionImporter {
    var name: String { get }
    func isAvailable() async -> Bool
    func snapshot() async throws -> Account
}

/// chain importers; first success wins, all-fail throws .allPathsFailed
final class CompositeImporter: SystemSessionImporter {
    let name = "composite"
    private let strategies: [SystemSessionImporter]
    init(strategies: [SystemSessionImporter]) { self.strategies = strategies }

    func isAvailable() async -> Bool {
        for s in strategies where await s.isAvailable() { return true }
        return false
    }

    func snapshot() async throws -> Account {
        var failures: [String] = []
        for s in strategies {
            do {
                return try await s.snapshot()
            } catch {
                failures.append("\(s.name): \(error)")
            }
        }
        throw SystemSessionError.allPathsFailed(failures)
    }
}
```

具体实现（M0.5 PoC 输出）：

```swift
// AccountsdImporter.swift — path A: ACAccountStore via AccountsdBridge.h
final class AccountsdImporter: SystemSessionImporter { }

// FileSystemImporter.swift — path B: read /var/mobile/Library/com.apple.itunesstored
final class FileSystemImporter: SystemSessionImporter { }

// KeychainImporter.swift — path C: SecItemCopyMatching on com.apple.itunesstored
final class KeychainImporter: SystemSessionImporter { }
```

### 5.5 `Core/SystemSession/AccountsdBridge.h`

```objc
// private framework; can't link directly. resolve via dlopen + KVC.
// objc wrapper is safer than calling -valueForKey: from swift on private classes.
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@interface ESAccountsdBridge : NSObject
+ (BOOL)isAvailable;
/// keys: email, dsid, altDSID, oauthToken (nullable), storefront (nullable)
+ (nullable NSDictionary *)copyAppleIDAccountInfoWithError:(NSError *_Nullable *_Nullable)errorOut;
@end

NS_ASSUME_NONNULL_END
```

### 5.6 `Core/Zip/IPAPatcher.swift`

```swift
import Foundation
import ZIPFoundation

protocol IPAPatcher {
    /// inject iTunesMetadata.plist + sinfs[] in place
    /// on throw the ipa is not trustworthy; caller should delete it
    func patch(ipaURL: URL, sinfs: [Sinf], metadata: [String: Any]) throws
}

final class IPAPatcherLive: IPAPatcher {
    func patch(ipaURL: URL, sinfs: [Sinf], metadata: [String: Any]) throws {
        unimplemented()
    }
}
```

### 5.7 `Core/Zip/PartialZipReader.swift`

```swift
import Foundation

/// read minimum bytes from a remote IPA to parse Info.plist
protocol PartialZipReader {
    func peekInfoPlist(at url: URL) async throws -> [String: Any]
}
```

### 5.8 `Core/Device/DeviceIdentifier.swift`

```swift
import Foundation

enum DeviceIdentifier {
    /// stealth: read from system (injected via SystemSessionImporter post M0.5)
    /// fallback: random 12-hex persisted to keychain
    static func current(vault: KeychainVault) throws -> String { unimplemented() }

    static func generateRandom() -> String {
        let chars = Array("0123456789ABCDEF")
        return String((0..<12).map { _ in chars.randomElement()! })
    }
}
```

### 5.9 `Core/Keychain/KeychainVault.swift`

```swift
import Foundation
import Security

protocol KeychainVault {
    func set(_ data: Data, for key: String) throws
    func get(_ key: String) throws -> Data?
    func remove(_ key: String) throws
    func allKeys() throws -> [String]
}

final class KeychainVaultLive: KeychainVault {
    private let service: String
    init(service: String = "com.evil0ctal.evilstore") { self.service = service }

    func set(_ data: Data, for key: String) throws { unimplemented() }
    func get(_ key: String) throws -> Data? { unimplemented() }
    func remove(_ key: String) throws { unimplemented() }
    func allKeys() throws -> [String] { unimplemented() }
}
```

### 5.10 `Core/TrollStore/TrollStoreBridge.swift`

```swift
import UIKit

protocol TrollStoreBridge {
    /// hand off the .ipa to TrollStore. returns false if the URL scheme call failed
    /// (typically: TrollStore not installed).
    @MainActor
    func install(ipaAt url: URL) -> Bool
    @MainActor
    func canHandleInstall() -> Bool
}

final class TrollStoreBridgeLive: TrollStoreBridge {
    @MainActor
    func canHandleInstall() -> Bool {
        UIApplication.shared.canOpenURL(URL(string: "apple-magnifier://")!)
    }

    @MainActor
    func install(ipaAt url: URL) -> Bool {
        guard var comps = URLComponents(string: "apple-magnifier://install") else { return false }
        comps.queryItems = [.init(name: "url", value: url.absoluteString)]
        guard let target = comps.url else { return false }
        UIApplication.shared.open(target, options: [:], completionHandler: nil)
        return true
    }
}
```

### 5.11 `Core/HTTP/HTTPClient.swift`（关键约束）

```swift
import Foundation

protocol HTTPClient {
    /// throttled URLSession.data; cookies and storefront headers handled by the client
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

actor URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let throttle: AsyncThrottle           // >=500ms default; see 1-doc §5 risk #1
    init(session: URLSession = .shared, minInterval: TimeInterval = 0.5) {
        self.session = session
        self.throttle = AsyncThrottle(minInterval: minInterval)
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await throttle.wait()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

actor AsyncThrottle {
    private let minInterval: TimeInterval
    private var lastSent: Date?
    init(minInterval: TimeInterval) { self.minInterval = minInterval }
    func wait() async {
        if let last = lastSent {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minInterval {
                try? await Task.sleep(nanoseconds: UInt64((minInterval - elapsed) * 1e9))
            }
        }
        lastSent = Date()
    }
}
```

### 5.12 `Util/Logger.swift`

```swift
import Foundation
import os

/// any log containing these fields must be redacted; violation = assertionFailure (consider raising to fatalError once CI is green)
enum SensitiveField: String, CaseIterable {
    case password, passwordToken, oauthToken, dsid, altDSID, guid, cookie
}

let logger = Logger(subsystem: "com.evil0ctal.evilstore", category: "default")

extension Logger {
    func info(_ msg: String, sanitize fields: [SensitiveField] = []) {
        var clean = msg
        for f in fields { clean = clean.replacingOccurrences(of: f.rawValue, with: "<\(f.rawValue)>") }
        self.info("\(clean, privacy: .public)")
    }
}
```

---

## 6. 构建与安装脚本

### 6.1 `Scripts/build_tipa.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
#
# build EvilStore and package as a TrollStore-installable .tipa
#
# usage:
#   Scripts/build_tipa.sh                     # Release -> build/EvilStore.tipa
#   Scripts/build_tipa.sh --debug             # Debug build
#   Scripts/build_tipa.sh --output PATH       # custom output path
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG="Release"
OUTPUT="$REPO_ROOT/build/EvilStore.tipa"
SCHEME="EvilStore"
WORKSPACE_OR_PROJ=("-project" "EvilStore.xcodeproj")
ENTITLEMENTS="$REPO_ROOT/EvilStore/Resources/entitlements.plist"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="Debug"; shift ;;
        --output) OUTPUT="$2"; shift 2 ;;
        *) echo "unknown arg: $1"; exit 1 ;;
    esac
done

command -v ldid >/dev/null || { echo "ldid missing; brew install ldid"; exit 1; }
[[ -f "$ENTITLEMENTS" ]] || { echo "entitlements not found: $ENTITLEMENTS"; exit 1; }

DERIVED="$REPO_ROOT/build/DerivedData"
ARCHIVE="$REPO_ROOT/build/EvilStore.xcarchive"
STAGE="$REPO_ROOT/build/stage"
mkdir -p "$REPO_ROOT/build"
rm -rf "$ARCHIVE" "$STAGE"

echo "==> archive ($CONFIG)"
xcodebuild \
    "${WORKSPACE_OR_PROJ[@]}" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    archive | (command -v xcbeautify >/dev/null && xcbeautify || cat)

APP_SRC="$ARCHIVE/Products/Applications/EvilStore.app"
[[ -d "$APP_SRC" ]] || { echo "EvilStore.app not in archive"; exit 1; }

echo "==> stage Payload/"
mkdir -p "$STAGE/Payload"
cp -R "$APP_SRC" "$STAGE/Payload/EvilStore.app"

echo "==> ldid fakesign with entitlements"
ldid -S"$ENTITLEMENTS" "$STAGE/Payload/EvilStore.app/EvilStore"
# also fakesign embedded dylibs/frameworks so SPM binaries don't fail amfi
find "$STAGE/Payload/EvilStore.app" -type f \( -name "*.dylib" -o -name "*.framework" \) -print0 \
    | while IFS= read -r -d '' f; do
        echo "    sign $f"
        ldid -S "$f"
    done

echo "==> zip -> $OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
( cd "$STAGE" && zip -qr "$OUTPUT" Payload )

echo "ok: $OUTPUT"
ls -lh "$OUTPUT"
```

### 6.2 `Scripts/bump_version.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
#
# bump marketing + build version in Configuration/Version.xcconfig
#
# usage:
#   Scripts/bump_version.sh patch        # 0.1.0 -> 0.1.1
#   Scripts/bump_version.sh minor        # 0.1.x -> 0.2.0
#   Scripts/bump_version.sh major        # 0.x.x -> 1.0.0
#   Scripts/bump_version.sh 1.2.3        # explicit
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/Configuration/Version.xcconfig"

current_marketing() {
    grep '^MARKETING_VERSION' "$VERSION_FILE" | awk -F= '{gsub(/ /,"",$2); print $2}'
}
current_build() {
    grep '^CURRENT_PROJECT_VERSION' "$VERSION_FILE" | awk -F= '{gsub(/ /,"",$2); print $2}'
}

bump_field() {
    local v="$1" field="$2"
    IFS=. read -r maj min pat <<<"$v"
    case "$field" in
        major) echo "$((maj + 1)).0.0" ;;
        minor) echo "${maj}.$((min + 1)).0" ;;
        patch) echo "${maj}.${min}.$((pat + 1))" ;;
    esac
}

cur="$(current_marketing)"
build="$(current_build)"

case "${1:-}" in
    major|minor|patch) new="$(bump_field "$cur" "$1")" ;;
    [0-9]*.[0-9]*.[0-9]*) new="$1" ;;
    *) echo "usage: $0 {major|minor|patch|X.Y.Z}"; exit 1 ;;
esac

new_build=$((build + 1))

sed -i.bak \
    -e "s/^MARKETING_VERSION.*/MARKETING_VERSION         = $new/" \
    -e "s/^CURRENT_PROJECT_VERSION.*/CURRENT_PROJECT_VERSION   = $new_build/" \
    "$VERSION_FILE"
rm -f "$VERSION_FILE.bak"

echo "version: $cur -> $new (build $build -> $new_build)"
```

### 6.3 `Scripts/install_local.sh`（可选）

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
#
# push build/EvilStore.tipa to a test iPhone
#
# default mode opens Finder so the user can AirDrop manually.
# ssh mode requires OpenSSH on the device (optional; not required by TrollStore).
#
# usage:
#   Scripts/install_local.sh
#   Scripts/install_local.sh ssh root@iphone.local /var/mobile/Downloads/
set -euo pipefail
TIPA="${1:-build/EvilStore.tipa}"
TIPA="$(realpath "$TIPA")"

if [[ "${1:-}" == "ssh" ]]; then
    HOST="$2"; DEST="$3"
    scp "$TIPA" "$HOST:$DEST"
    echo "scp ok: $HOST:$DEST -- open in Filza to install"
else
    open -a "Finder" "$(dirname "$TIPA")"
    echo "in Finder: right-click EvilStore.tipa -> Share -> AirDrop -> iPhone"
fi
```

### 6.4 `Scripts/lint.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
#
# run swiftformat + swiftlint; skip silently if either tool is missing
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if command -v swiftformat >/dev/null; then
    swiftformat --lint EvilStore EvilStoreTests
else
    echo "skip: swiftformat not found (brew install swiftformat)"
fi

if command -v swiftlint >/dev/null; then
    swiftlint lint --quiet
else
    echo "skip: swiftlint not found (brew install swiftlint)"
fi
```

---

## 7. 编码规范与项目约定

### 7.1 Swift 代码风格

- 缩进 4 空格；最大行宽 120；左大括号同行。
- 私有属性 / 函数加 `private`，模块边界用 `internal`（默认）；`public` 仅在 v2 拆 SPM 时才用。
- 优先 `struct` over `class`；需要引用语义或继承再用 `class final`。
- 错误处理：所有外部边界（HTTP、文件、Keychain、私有 framework）必须 `throws`；内部纯逻辑可 `Result` 或 `enum` 表达失败。
- **绝不**写 `try?` 吞错——要么处理，要么向上 throw。

### 7.2 命名

- 类型 `PascalCase`，属性 / 函数 `camelCase`，常量 `camelCase`（**不**用 `kFoo`）。
- 文件名 = 主类型名（`AppStoreClient.swift` 含 `protocol AppStoreClient`）；扩展文件用 `+` 前缀（`AppStoreClient+Search.swift`）。
- 测试文件 `<TypeName>Tests.swift`，单测类 `final class <TypeName>Tests: XCTestCase`。

### 7.3 模块边界

- `UI` 不直接调 `Core`，必须经 `Domain`。
- `Domain` 不依赖 `UIKit / SwiftUI`。
- `Core` 不依赖 `Domain`（依赖反转：`Domain` 注入 `Core` 的 protocol）。

### 7.4 敏感字段

凡涉及 `password / passwordToken / oauthToken / DSID / GUID / cookies`：
- **不进 `Codable` 的 `description` / `debugDescription`**（用 `CustomDebugStringConvertible` 显式覆盖）。
- **不进日志**（`Logger.info` 提供脱敏 helper）。
- **不进 `NSUserDefaults`**（一律 Keychain）。
- **不在崩溃报告里**（`os_log` 用 `privacy: .private` 或 `.sensitive`）。

### 7.5 ObjC 桥

- 仅在调用私有 framework（`accountsd`）、读 `NSURLCredentialStorage` 等系统 API 时使用 ObjC。
- ObjC 文件命名前缀 `ES`（`ESAccountsdBridge`），避免与系统 / Apple 类名冲突。
- bridging header 路径 `EvilStore/EvilStore-Bridging-Header.h`，xcconfig 里：

  ```xcconfig
  SWIFT_OBJC_BRIDGING_HEADER = EvilStore/EvilStore-Bridging-Header.h
  ```

### 7.6 资源 / 文件路径

所有跨进程 / 跨用户能看到的路径走 `FileLayout`：

```swift
enum FileLayout {
    static let root = URL(fileURLWithPath: "/var/mobile/Media/EvilStore")
    static var downloads: URL { root.appendingPathComponent("Downloads") }
    static var cache: URL     { root.appendingPathComponent("Cache") }
    static var logs: URL      { root.appendingPathComponent("Logs") }

    static func ensureDirs() throws {
        let fm = FileManager.default
        for u in [downloads, cache, logs] {
            try fm.createDirectory(at: u, withIntermediateDirectories: true)
        }
    }
}
```

### 7.7 消息风格 — 注释、Commit、Release Notes

**硬规则**：所有写给"人看"的英文文本——源码注释、git commit message、GitHub release notes、PR 标题——都遵循下面这套，不允许偏移。文档（`docs/*.md`）不在此列，可继续中文。

#### 7.7.1 总原则

- **English only.** 不混中文，不夹拼音。
- **Concise.** 注释一行能说清的不写两行；commit subject ≤ 50 字符，body 每行 ≤ 72 字符。
- **No marketing.** 删掉所有形容词副词："robust"、"production-grade"、"comprehensive"、"seamless"、"powerful"、"elegant" 全禁。
- **No AI tells.** 删掉所有 LLM 高频套语：`Let me ...`、`I'll ...`、`Here's ...`、`This commit ...`、`In this PR we ...`、emoji 开头、`✨`、`🚀`、`📝`、`🔥`、收尾的 `Hope this helps!`、`Let me know if ...`。
- **Imperative present.** 写命令式现在时——不是"fixed bug"，不是"fixes bug"，是 `fix bug`。
- **What it is, not what we did.** 注释解释代码现状，不解释开发过程；commit 描述行为变更，不写"我加了"。
- **Why over what.** 代码本身能说"做了什么"，注释说"为什么"。

#### 7.7.2 参考来源

- **Linux kernel** (`Documentation/process/submitting-patches.rst`)：subject = `subsystem: short imperative phrase`；body 解释问题与修法；trailers (`Signed-off-by:`, `Fixes:`, `Reported-by:`) 在末尾。
- **git itself** (`git log --oneline | head` 是教科书)：`subsys: do the thing` 一行说尽。
- **curl** (`docs/CONTRIBUTE.md`)：subject 50 字符内，body 解释 _why_，参考 issue 用 `Closes #N` / `Ref: #N`。
- **sqlite**：注释极简，`/* ... */` 单行说明意图；模块开头有简短不啰嗦的 file-level header。

#### 7.7.3 Commit message 格式

```
<area>: <imperative subject under 50 chars>

<optional body, 72-char wrap, explains why; multi-paragraph ok.>
<reference issues like: Closes #12, Fixes: abc1234>
```

`<area>` 取仓库内自然存在的小写短词：`appstore`、`http`、`zip`、`stealth`、`ui`、`ci`、`docs`、`build`、`scripts`、`tests`。Conventional-commits 的 `feat:` / `fix:` 不强制，**但若用必须英文**（不是 `feat: 项目骨架...`）。

**好例子**：

```
build: stage Payload before ldid fakesign

ldid mutates the binary in place, so the archive output must be copied
to a scratch dir first, otherwise xcodebuild's next archive would pick
up the modified Mach-O and refuse to re-archive.

Closes #4
```

```
stealth: try accountsd before falling back to filesystem

ACAccountStore returns a fresher passwordToken than the on-disk plist
on iOS 16+ where storeaccountd rotates tokens hourly.
```

```
http: throttle storefront calls to 500ms

Apple's WAF rate-limits at ~3 req/s for Configurator UA. Spacing keeps
list-versions probes from triggering 429s.
```

```
docs: explain why simulator tests are dropped
```

**反面例子**（出现就 reject）：

```
✨ feat: Implement comprehensive app store client with robust error handling 🚀

This commit introduces a production-grade implementation of the App Store
protocol layer that I built using the patterns from ApplePackage. It
features...
```

问题：emoji、AI 套话、形容词堆叠、第一人称、超长 subject、"introduces"、"comprehensive"、"production-grade"、"robust"。

#### 7.7.4 源码注释

**默认不写注释**。当代码本身已经表达"做了什么"时，再写注释只会重复。只在以下情形写：

1. 不写就会让下个读到的人困惑（unobvious 行为、绕开 bug、外部 API 怪癖）。
2. 解释 _why_，不解释 _what_。

```swift
// good: 说明 why
// Apple returns 302 even for valid creds; follow Location ourselves
// because URLSession's auto-redirect strips the auth-side cookies.
var request = makeAuthRequest(...)

// bad: 重复 what
// create a new mutable request
var request = makeAuthRequest(...)
```

**风格**：单行注释 `//`，句首小写，结尾不加句号（命令式短语）。多行注释罕用，必要时 `/* ... */`，每行也是命令式短句。

```swift
// drop the trailing newline storeaccountd appends
let token = raw.trimmingCharacters(in: .newlines)

/*
 * Plist payload stays XML, not binary.
 * Apple's gateway rejects binary plist on this endpoint as of 2024-11.
 */
```

文件级 header **必须写**（SPDX + 两行 copyright，详见 §7.8）。**不要写** Xcode 默认生成的 `Created by ... on ...` / 项目描述 / 长篇 license boilerplate —— 这些已被 SPDX 行替代。

**ObjC** 注释同款 (`//` 优先)。**Shell** 用 `#`，同样 imperative + 小写 + 无句号。

#### 7.7.5 Release notes / Tag annotation

GitHub release body 走下面这块固定模板（参考 git 项目 `Documentation/RelNotes/*.txt`）：

```
EvilStore 0.3.0

Highlights
----------
* dual-mode login: stealth (system session) with manual fallback
* 2fa flow handles failureType=5005 explicitly

Fixes
-----
* http: don't follow 302 across pods (lost cookies)

Known issues
------------
* iOS 17.0 stealth path A occasionally returns nil DSID; manual login
  works as fallback.
```

不写"This release is a major milestone..."、"We're excited to..."、`✨`、感谢清单不堆砌（合并到一行 `Thanks: <names>` 即可）。

#### 7.7.6 PR 标题与描述

- 标题 = commit subject 同款规则。
- 描述模板（kernel-style，简短）：

  ```
  ## what
  one-line restatement of the change.

  ## why
  bullet points of the motivation; reference issue numbers.

  ## test
  what was run, on which device + iOS version.
  ```

  无需 "Checklist"、"Screenshots"（除非 UI 改动）、"Breaking changes" 这种 section 头，需要时再加。

#### 7.7.7 自检表

提交前过一遍：

- [ ] subject ≤ 50 字符，imperative，无句号
- [ ] 全英文，无中文 / 拼音
- [ ] 无 emoji（除非是表示构建状态的固定符号，例如 release 中 `*` 列表项）
- [ ] 无 "I"、"we"、"my"、"this commit"、"this PR"
- [ ] 无形容词副词（`great`、`comprehensive`、`robust` 等）
- [ ] 注释回答 _why_，不重复 _what_
- [ ] 新建源码文件带上 §7.8 文件头

不过自检的 commit / PR 直接 reject。

### 7.8 文件头签名 — SPDX + Copyright

**硬规则**：所有新建的源码文件（Swift / ObjC / C / shell / Python）都以下面这两行开头，紧贴 shebang（如有）之后：

```
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
```

**仅此两行**。不再加 `Created by ... on ...`、不再加文件描述、不再贴 GPL 全文 boilerplate —— 项目根 `LICENSE` 已有完整 GPLv2（339 行），逐文件复述纯属噪声。

参考来源：Linux kernel 自 2017 年起全量采用 SPDX 短标识符（见 `Documentation/process/license-rules.rst`）；现代主流 GPL 项目（systemd、btrfs-progs、util-linux）也全部走 SPDX。这种写法 2 行能说清的事不写 17 行。

#### 7.8.1 各语言模板

**Swift / Objective-C / Objective-C++**：

```swift
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

// ... actual code ...
```

**ObjC header (`*.h`)**：

```objc
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// ...
NS_ASSUME_NONNULL_END
```

**Shell**（shebang 在前，license 在后）：

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

set -euo pipefail
# ...
```

**Python**（同 shell）：

```python
#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
```

**C**（v2 helper 阶段会用到）：

```c
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

#include <stdio.h>
```

**Plist / XML / Markdown / YAML**：**不加**（注释语法各家不同，且这些是配置/文档资源，license 由仓库根 `LICENSE` + `README` 说明已足够）。

#### 7.8.2 哪些文件 **不** 加

- `Configuration/*.xcconfig` — 构建配置，加注释会污染 `xcodebuild` 的输出。
- `Resources/Info.plist` / `Resources/entitlements.plist` — Apple plist 工具不识别注释。
- `Resources/Assets.xcassets/*` — 资源目录，二进制 + JSON。
- `*.md` / `docs/*` — 文档，非源码。
- `.gitignore` / `.editorconfig` / `.swiftformat` / `.swiftlint.yml` — 工具配置，约定俗成不带 license。
- 第三方 vendor 源码（`ThirdParty/*`）—— 保留上游原 header，不替换。

#### 7.8.3 年份策略

- 年份就是文件**首次创建**那年，**不**写 `2024-2026` 区间，**不**每次修改都更新年份。
- 文件被大改 / 重写时也不动年份（git history 是真理之源，不靠 header 标变更）。
- 项目跨年时新文件用新年份，老文件保留原年份。

#### 7.8.4 多作者情形

后续如果有外部贡献者：

```
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
// Copyright (C) 2027 Some Contributor <them@example.com>
```

每行一作者，年份独立。这条等真有 PR 进来时再启用，v1 阶段都是 Evil0ctal 一人。

#### 7.8.5 自动化检查

`Scripts/lint.sh` 增加一道检查（M0 完成时实现）：

```bash
# fail if any tracked .swift / .m / .h / .sh under source dirs
# is missing the SPDX header
git ls-files 'EvilStore/**/*.swift' 'EvilStore/**/*.m' 'EvilStore/**/*.h' 'Scripts/*.sh' \
    | xargs -I{} sh -c 'head -3 "{}" | grep -q "SPDX-License-Identifier: GPL-2.0" || { echo "missing SPDX: {}"; exit 1; }'
```

CI 跑 `lint.sh` 时这条会卡住没头的文件。

#### 7.8.6 LICENSE 文件本身

仓库根 `LICENSE` 已是 GPLv2（339 行，标准 FSF 文本）。**不要替换、不要修改、不要拼接**——SPDX 标识符通过 [SPDX License List](https://spdx.org/licenses/GPL-2.0.html) 与该文本绑定，任何改动都会让识别工具（github-linguist、scancode）报错。

`README.md` 末尾应有一段 license note（v0.2 §13.8 待补的 README quickstart 一并加），示例：

```
## License

GPL-2.0-only. See [LICENSE](./LICENSE).
```

---

## 8. 测试策略

> **v0.2 重写**：测试策略**只承认真机 + TrollStore 的运行结果**。Simulator 既装不了 TrollStore，也没有 `accountsd` 真实账户、`/var/mobile/Library/com.apple.itunesstored/`、私有 entitlements 行为——在 simulator 上"测试通过"对本项目而言**没有意义**，会给出虚假信心。
>
> 所以：
> - **不在 CI 上跑 `xcodebuild test`**（会强制走 simulator，等于纸面绿灯）。
> - **不写依赖系统会话状态的"伪 mock"测试**（坚持只用纯字节 fixture 跑得通的部分）。
> - **真实功能验证全部走真机** + TrollStore + 一份手测清单。

### 8.1 测试金字塔（按 EvilStore 的现实重切）

| 层 | 跑在 | 用途 | 触发时机 |
|---|---|---|---|
| **静态检查** | macOS / CI | swiftformat、swiftlint、`xcodebuild build`（不跑测试，只编译过） | 每次 push / PR |
| **纯逻辑单测** | 真机（device target） | 不依赖系统状态的字节级单元（plist 编解码、zip 打补丁、binary cookies 解析、URL 构造、节流器、错误码映射） | 每次构建 TIPA 前手动 `Cmd+U`，在装着 TrollStore 的真机上跑一次 |
| **协议联通测试** | 真机 + 真 Apple ID | 用 stub URLProtocol 喂 plist fixture，验证 `AppStoreClient` 的请求构造与响应解析 | M1 / M2 / M3 完成时手动 |
| **端到端（手测）** | 真机 + TrollStore + 真账号 | 走完完整流程：登录 → 搜索 → 列版本 → 下载 → 安装 → 启动被装 App | 每个 milestone 验收 + 每个 release 候选 |

> **没有 simulator 这一档**。Xcode 中 simulator 当 SwiftUI 预览工具用，不当测试目标用。

### 8.2 真机测试矩阵

至少在下列任一组合上跑通才能 release：

| 设备 | iOS 版本段 | 必测路径 |
|---|---|---|
| iPhone（A12+） | 14.x | M0、M1 stealth 路径 A |
| iPhone（A12+） | 15.x | 同左 + 路径 B |
| iPhone（A12+） | 16.x | 同左（路径 C 验证） |
| iPhone | 17.0 / 16.7 RC | 同左（路径 A 已知较脆） |

**没有完整四档设备的开发期妥协**：至少一台主测设备覆盖 M0–M4；其它版本通过社区 issue 反馈逐步补。

### 8.3 单测 fixture（仍要写，仍要受版本控制）

虽然不在 simulator 上跑，单测代码本身仍是有价值的——它在真机上跑（`xcodebuild test -destination 'generic/platform=iOS'` 装上后 `Cmd+U`）。fixture 文件清单：

```
EvilStoreTests/Fixtures/
├── login_success.plist
├── login_2fa_required.plist          # failureType="" + customerMessage="MZFinance.BadLogin..."
├── login_5005_bad_2fa.plist
├── list_versions_response.plist      # songList[0].metadata.softwareVersionExternalIdentifiers
├── download_response.plist           # songList[0].URL/sinfs/metadata
├── purchase_success.plist
├── purchase_5002_already_owned.plist
├── tiny_app.ipa                      # 50KB IPA fixture for IPAPatcher
└── sample.binarycookies              # 2-cookie sample
```

URL stub helper（与 v0.1 同款，仅改注释）：

```swift
// EvilStoreTests/Helpers/StubURLProtocol.swift
final class StubURLProtocol: URLProtocol {
    static var stubs: [URLRequest: (Int, Data, [String: String])] = [:]
    override class func canInit(with request: URLRequest) -> Bool { stubs[request] != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let (status, body, headers) = Self.stubs[request] else { return }
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

### 8.4 IPAPatcher 单测

跑在真机的 test runner 上：
- `Tests/Fixtures/tiny_app.ipa` 是手工构造的 ~50KB 最小 IPA（`Payload/Tiny.app/{Info.plist, Tiny}`，主二进制 4 字节占位）。
- 喂 fake `Sinf` + fake `metadata`，断言：
  - `iTunesMetadata.plist` 能被 `PropertyListSerialization` 解回原 dict。
  - `Payload/Tiny.app/SC_Info/Tiny.sinf` 字节内容一致。
  - 原有条目都还在。

### 8.5 BinaryCookiesParser 单测

- 用 Apple Binary Cookies v0x100 规范手工构造样本（~64 字节）；
- 字段往返一致。

### 8.6 SystemSessionImporter — 真机 only

`AccountsdImporter` / `FileSystemImporter` **不写在 simulator 跑得动的 mock 单测**——那种测试通过给出的信号都是假的。它们只在真机上以"手测脚本"形式验证：

```
EvilStoreTests/ManualScripts/stealth_smoke.swift
```

提供一个 debug-only Settings 入口（`#if DEBUG`）"Run Stealth Diagnostics"，按下后跑 4 条路径、把脱敏摘要写到一份 markdown 报告里，AirDrop 给开发者。M0.5 PoC 的产物之一就是这个 diagnostic 工具。

### 8.7 端到端手测清单（每个 release 必跑）

放在 `docs/test_plan.md`（M5 创建），结构：

```
## E2E test plan

device: iPhone XS, iOS 15.7.9, TrollStore 2.0.12
account: secondary@icloud.com (storefront US)

[ ] cold launch under 2s
[ ] settings shows borrowed apple-id email
[ ] search "Telegram" returns >= 3 results
[ ] open detail, version timeline shows >= 10 entries
[ ] pick version v9.7.1, tap download, progress reaches 100%
[ ] downloaded ipa contains iTunesMetadata.plist + SC_Info/*.sinf
[ ] tap install -> trollstore prompt -> home screen icon appears
[ ] launch installed app, basic feature works
```

每条不通过的项 → GitHub issue + 一定不能 release。

### 8.8 真机测试为什么不上 CI

- GitHub Actions 没有官方 iPhone runner。
- 自建 self-hosted runner 接上越狱 / TrollStore 设备风险高、维护成本高，开源项目不建议。
- 折中：CI 只做"build + lint"绿灯，**真功能验证由人**按 §8.7 跑。

如果以后社区有人贡献 self-hosted runner，本节再扩。

---

## 9. CI / CD（GitHub Actions）

### 9.1 `.github/workflows/build.yml`

```yaml
name: Build TIPA

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app

      - name: Install ldid
        run: brew install ldid xcbeautify

      - name: Cache DerivedData
        uses: actions/cache@v4
        with:
          path: build/DerivedData
          key: dd-${{ runner.os }}-${{ hashFiles('EvilStore.xcodeproj/project.pbxproj', 'Configuration/*.xcconfig') }}

      - name: Build TIPA
        run: Scripts/build_tipa.sh

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: EvilStore-tipa
          path: build/EvilStore.tipa

      - name: Release on tag
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: build/EvilStore.tipa
          generate_release_notes: true
```

### 9.2 `.github/workflows/lint.yml`

> **v0.2 改动**：删除 simulator 上的 `xcodebuild test` 任务（参见 §8）。CI 只做"格式 + 编译"两道绿灯，真功能验证靠 §8.7 真机手测清单。

```yaml
name: lint

on: [push, pull_request]

jobs:
  format:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: brew install swiftformat swiftlint
      - run: Scripts/lint.sh

  compile:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s /Applications/Xcode_15.4.app
      - run: brew install xcbeautify
      - name: build only (no tests)
        run: |
          xcodebuild build \
            -project EvilStore.xcodeproj \
            -scheme EvilStore \
            -destination 'generic/platform=iOS' \
            CODE_SIGNING_ALLOWED=NO | xcbeautify
```

> 不在 CI 跑测试是有意为之 —— 详见 §8.8。要在 PR 上证明改动可用，截图或 AirDrop TIPA 给 reviewer 真机过一遍 §8.7 清单。

---

## 10. Milestone 任务拆解表（M0 → M5）

> 每行的 "新增 / 修改" 直接告诉你"打开哪些文件开始写代码"。

### M0 — 骨架（约 0.5 天）

| 任务 | 新增 / 修改 |
|---|---|
| 建 Xcode project | `EvilStore.xcodeproj` |
| 落 xcconfig 四件套 | `Configuration/{Base,Debug,Release,Version}.xcconfig` |
| Info.plist + entitlements（最小集） | `EvilStore/Resources/{Info,entitlements}.plist` |
| 占位 SwiftUI | `EvilStore/App/EvilStoreApp.swift` / `AppDelegate.swift` / `UI/Root/RootView.swift` |
| 构建脚本可用 | `Scripts/build_tipa.sh` `bump_version.sh` `lint.sh` |
| 一个空测试 | `EvilStoreTests/EvilStoreTests.swift` |
| **验收** | `Scripts/build_tipa.sh` 通；TrollStore 装上后桌面有图标，启动看到 RootView |

### M0.5 — Stealth PoC（独立 3 号文档详解，1~2 天）

| 任务 | 新增 / 修改 |
|---|---|
| `accountsd` ObjC 桥 | `Core/SystemSession/AccountsdBridge.{h,m}` |
| 路径 A 实现 | `Core/SystemSession/AccountsdImporter.swift` |
| 路径 B 实现 | `Core/SystemSession/FileSystemImporter.swift` |
| .binarycookies 解析 | `Core/SystemSession/BinaryCookiesParser.swift` |
| Composite 链 | `Core/SystemSession/{SystemSessionImporter,CompositeImporter}.swift` |
| Settings UI 显示当前 stealth 状态 | `EvilStore/UI/Settings/StealthDiagnosticsView.swift` |
| entitlements 扩展 | 追加 §4.12 中私有 ent |
| **验收** | iOS 14 / 15 / 16 / 17 至少一台设备上能从系统读出可用 `Account` 并打印（脱敏后）摘要 |

### M1 — Stealth + Manual 双模式登录（约 2 天）

| 任务 | 新增 / 修改 |
|---|---|
| HTTP 栈 | `Core/HTTP/{HTTPClient,PlistPayload,CookieJar}.swift` |
| Endpoints + Bag | `Core/AppStoreClient/{Endpoints,Bag}.swift` |
| Lookup + Search | `Core/AppStoreClient/{Lookup,Search}.swift` |
| Authenticate（manual fallback） | `Core/AppStoreClient/Authenticate.swift` |
| AccountManager（多账号 + 双源） | `Domain/AccountService.swift` + 持久化 |
| Login UI（manual 模式专用） | `EvilStore/UI/Login/*.swift` |
| 启动选账号弹窗 | `EvilStore/UI/Login/AccountPickerView.swift` |
| **验收** | (a) 设备已登录 App Store → 启动 5 秒内零交互拉到 stealth account；(b) 未登录 → manual 流程可用；(c) 切账号后 search 用对应区域 |

### M2 — 版本列表（约 1 天）

| 任务 | 新增 / 修改 |
|---|---|
| ListVersions | `Core/AppStoreClient/ListVersions.swift` |
| PartialZipReader | `Core/Zip/PartialZipReader.swift` |
| 缓存层 | `Domain/VersionResolverService.swift`（key = `appID:externalID`） |
| Detail UI | `EvilStore/UI/Detail/*.swift` |
| **验收** | 任选一个常用 App 列出 ≥10 历史版本，含版本号 + 发布时间 |

### M3 — 下载与补丁（约 2 天）

| 任务 | 新增 / 修改 |
|---|---|
| Purchase（已购续约） | `Core/AppStoreClient/Purchase.swift` |
| Download | `Core/AppStoreClient/Download.swift` |
| IPAPatcher（in-place 注入） | `Core/Zip/IPAPatcher.swift` |
| DownloadEngine（断点续传 + 队列） | `Domain/DownloadService.swift` |
| Downloads UI | `EvilStore/UI/Downloads/*.swift` |
| **验收** | 拉一个免费 App 旧版，落地的 .ipa `unzip -l` 见 `iTunesMetadata.plist` + `SC_Info/*.sinf` |

### M4 — 安装回环（约 0.5 天）

| 任务 | 新增 / 修改 |
|---|---|
| TrollStoreBridge | `Core/TrollStore/TrollStoreBridge.swift` |
| 错误码文案 | `Core/TrollStore/TSErrorCatalog.swift` |
| Library UI（已下载列表） | `EvilStore/UI/Library/*.swift` |
| **验收** | 在 EvilStore Library 点 Install → TrollStore 接管 → 桌面出现新图标 → 可启动 |

### M5 — 体验打磨（约 2 天）

进度条 / 错误码文案完善 / 断点续传 / 下载队列 / 日志导出 / stealth 会话过期检测 / Localization。

---

## 11. 首日 Checklist — 从空仓库到桌面图标

> 出问题严格按本表自顶向下排查。

- [ ] `brew list ldid coreutils jq xcbeautify` — 4 项都安装好
- [ ] `xcode-select -p` → `/Applications/Xcode.app/...`，且 `xcodebuild -version` ≥ 15.0
- [ ] Xcode 新建 iOS App，Bundle ID `com.evil0ctal.evilstore`，SwiftUI + Swift
- [ ] 关闭 Xcode，按 §3 重组目录（保留 `EvilStoreApp.swift` 等核心）
- [ ] 创建 `Configuration/{Base,Debug,Release,Version}.xcconfig`，内容粘贴 §4.5–4.8
- [ ] Xcode 重开 → Project → Info → Configurations → Debug 指向 `Debug.xcconfig`，Release 指向 `Release.xcconfig`（可能要删掉默认值后再设）
- [ ] Xcode → Project → Build Settings → Combined → 验证 `IPHONEOS_DEPLOYMENT_TARGET=14.0`、`CODE_SIGNING_ALLOWED=NO`
- [ ] 创建 `EvilStore/Resources/Info.plist`、`entitlements.plist`（粘贴 §4.10、§4.11）
- [ ] xcconfig 中 `INFOPLIST_FILE` 指向新 Info.plist；旧 `EvilStore-Info.plist`（Xcode 默认）删掉
- [ ] `EvilStoreApp.swift` / `AppDelegate.swift` / `RootView.swift` 内容粘贴 §4.13–4.15（含 §7.8 SPDX 头）
- [ ] Xcode "Product → Build" 通过（无签名警告即可，签名 NO 是预期）
- [ ] `Scripts/build_tipa.sh` 执行成功，生成 `build/EvilStore.tipa`
- [ ] `unzip -l build/EvilStore.tipa | head` 见 `Payload/EvilStore.app/EvilStore`
- [ ] `ldid -e build/stage/Payload/EvilStore.app/EvilStore | head` 见 `<key>com.apple.private.security.no-sandbox</key>` 等条目
- [ ] AirDrop / Filza 把 .tipa 推到 iPhone
- [ ] TrollStore 打开 → 见 EvilStore 图标 + 详情 → 点 Install → 桌面出现 EvilStore 图标
- [ ] 启动 EvilStore → 见 Tab Bar + "Hello, EvilStore" → ✅ M0 完成
- [ ] `head -3 EvilStore/App/EvilStoreApp.swift` 见 SPDX 头（§7.8）
- [ ] `git add . && git commit -m "build: skeleton boots under trollstore"`（参考 §7.7）

**常见坑**：

| 现象 | 原因 / 修复 |
|---|---|
| `xcodebuild` 报 "No signing certificate" | 检查 `CODE_SIGNING_ALLOWED=NO` 是否生效；xcconfig 重新关联 |
| 装上但启动闪退 | `ldid` 没把 entitlements 写进二进制 → `ldid -e` 验证；或 entitlements 里有非法 key（错单词） |
| TrollStore 报 "encrypted main binary"（错误 180） | xcconfig 没关 bitcode 或被 Xcode 加密 → 加 `ENABLE_BITCODE = NO` |
| TrollStore 报 179（系统 App 同 ID） | bundle id 撞了 → 改成不与系统 App 冲突的值 |
| 启动后 `NSLog` 的 launched 没出现 | bundle id 有问题或没 ldid → 重做 ldid 步骤 |

---

## 12. 协作与版本约定

### 12.1 分支

- `main` — 始终可构建可装；任何提交前 lint + tests 必过。
- `feat/m0.5-stealth-poc` 等特性分支 → PR → squash merge → main。
- v0.x.0 时 tag `v0.x.0`，CI 自动发 release（含 .tipa）。

### 12.2 Commit message

格式与示例**全部走 §7.7**。摘要：

```
<area>: <imperative subject under 50 chars>

<optional body, 72-char wrap, explains why>
<trailers, e.g. Closes #12 / Fixes: abc1234>
```

`<area>` 用仓库内自然存在的小写短词（`appstore` / `http` / `zip` / `stealth` / `ui` / `ci` / `docs` / `build` / `scripts` / `tests`）。

**硬要求**：英文 only；imperative；无 emoji / 无第一人称 / 无形容词堆叠；自检过 §7.7.7 的 6 条清单再 push。

不挂 `Co-Authored-By` 标签（用户全局设置已禁用）。

### 12.3 文档与代码同步

- 任何破坏性的协议字段调整、entitlements 增删、文件布局改动 → **先改 1 / 2 号文档**再改代码，PR 描述里引用对应章节。
- M0.5 PoC 完成后产出 3 号文档；M3 完成后产出 5 号文档（IPA 补丁与安装流水线细节）。

### 12.4 版本号节奏

- `0.1.0` — M0 骨架
- `0.2.0` — M0.5 Stealth PoC 验证通过
- `0.3.0` — M1 双模式登录
- `0.4.0` — M2 版本列表
- `0.5.0` — M3 下载补丁
- `0.6.0` — M4 安装回环
- `0.7.0` — M5 打磨
- `1.0.0` — 全功能 + 文档齐全 + 一轮真机回归

---

## 13. 审计变更记录（v0.1 → v0.3）

> 用户审阅 v0.1 后提出两项硬约束：(a) 注释 / commit / release 信息走简洁英文 + 内核风格、去 AI 味；(b) 测试策略只承认真机 + TrollStore，simulator 不算数。本节记录由此触发的全文调整，便于 review 时定位。

### 13.1 §7 新增 §7.7 — Message Style（English-only · kernel-flavored）

新增 7 个子条款，**对全项目英文文本（注释 / commit / release / PR）形成硬约束**：

- **7.7.1 总原则**：English only；concise；no marketing；no AI tells（删 `Let me ...` / `I'll ...` / `Here's ...` / `In this PR we ...` / `✨🚀📝🔥` / 收尾 `Hope this helps!`）；imperative present；解释 _why_ 不重复 _what_。
- **7.7.2 参考来源**：Linux kernel `submitting-patches.rst`、git 自身、curl `CONTRIBUTE.md`、sqlite。
- **7.7.3 Commit 格式**：`<area>: <subject under 50 chars>` + 可选 72-char wrap body + trailers。给了 4 个好例子 + 1 个反面例子。
- **7.7.4 源码注释**：默认不写；写就解释 _why_；单行 `//`、句首小写、句尾不加句号；不写 file-level header。
- **7.7.5 Release notes**：固定模板 `Highlights / Fixes / Known issues`，参考 git `RelNotes`，禁止"This release is a major milestone..."。
- **7.7.6 PR 模板**：kernel-style，`## what / ## why / ## test` 三段。
- **7.7.7 自检表**：6 条 push 前必过的清单。

### 13.2 §8 测试策略整体重写 — 真机 + TrollStore only

**触发**：用户指出 simulator 装不了 TrollStore，本项目的所有特殊路径（私有 entitlements / `accountsd` 真账户 / 非沙箱文件系统 / TrollStore install URL）在 simulator 上**根本不成立**。在 simulator 上跑出来的"绿"是假的。

**改动**：
- 删除 v0.1 §8.1 的"Unit 跑在 macOS / iOS Simulator"提法。
- 新 §8.1 测试金字塔分四档：静态检查 / 纯逻辑单测（真机 device target）/ 协议联通（真机）/ E2E 手测（真机 + TrollStore）。**没有 simulator 这一档**。
- 新 §8.2 真机测试矩阵：iOS 14 / 15 / 16 / 17 各一台为目标。
- §8.3 fixture 列表保留，但明示"在真机 test runner 跑"。
- §8.6 `SystemSessionImporter` 不写 simulator mock 单测——会给假信号；改用 debug-only Settings 入口"Run Stealth Diagnostics"，PoC 阶段产出脱敏 markdown 报告。
- 新增 §8.7 端到端手测清单模板（写到 `docs/test_plan.md`，每个 release 必跑）。
- 新增 §8.8 解释"为什么不上 CI"（GitHub 没 iPhone runner，self-hosted 风险高）。

### 13.3 §9 CI workflow 重写 — build-only

- 删除原 `lint.yml` 中的 `xcodebuild test ... -destination 'iOS Simulator'` job。
- 替换为 `compile` job：`xcodebuild build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`。
- 末尾加注："不在 CI 跑测试是有意为之，详见 §8.8。要在 PR 上证明改动可用，截图或 AirDrop TIPA 给 reviewer 真机过一遍 §8.7 清单。"

### 13.4 注释 / 脚本英化（按 §7.7 走一遍）

逐文件英化：
- §4.13 / §4.14 `EvilStoreApp.swift` / `AppDelegate.swift` 占位代码内注释。
- §4.16 `EvilStoreTests.swift` 占位代码内注释。
- §5.1–5.12 所有 Swift / ObjC 类型 / protocol / 字段说明注释（保留对外语义注释，去掉中文随笔）。
- §6.1 `build_tipa.sh` 全文 — 错误信息、stage 注释、emoji 移除（`✅` → `ok:`）。
- §6.2 `bump_version.sh` — usage 与错误提示英化。
- §6.3 `install_local.sh` — emoji `✅👉` 删除，消息英化。
- §6.4 `lint.sh` — skip 提示英化。

### 13.5 Commit 示例英化

- §0 步骤 8：`feat: 项目骨架可被 TrollStore 安装` → `build: skeleton boots under trollstore`。
- §11 首日 checklist 末尾同款替换。
- §12.2 章节内容整体重写——删除"中英文均可"，改为引用 §7.7 + 强制清单。

### 13.6 文档头版本号 v0.1 → v0.2

封面版本与日期同步更新。

### 13.7 仍未变更（避免误读）

- §1 工具链（Xcode + xcodebuild + 自写 TIPA 脚本）—— 维持。
- §3 目录树 —— 维持，`EvilStoreUITests/` 仍然标 🔜（M5 之后真机回归走 §8.7 手测清单）。
- §4.5–4.10 / §4.11 / §4.12 entitlements 切分 —— 维持。
- §10 milestone 拆解表 —— 维持，但 M0 / M0.5 验收条件中"装上后"始终意味着 TrollStore + 真机。
- §11 首日 checklist 步骤数 —— 维持。
- §12.4 版本号节奏 —— 维持。

### 13.8 Open question

- 是否给 `EvilStore` 这个仓库的 `README.md` 顶部也加一段简短英文 quickstart（参考 curl/sqlite 的 README 风格）？目前 README 仅 `# EvilStore` 一行。**建议在 M0 首个 commit 时同步加，与本项目"对外文本英文 only"的约束一致。** 本文档暂不展开模板，下次 PR 我们一起拍板。

---

### 13.9 v0.2 → v0.3 — 追加 §7.8 文件头规则（SPDX + Copyright）

**触发**：用户指定项目走 GPLv2 开源（`LICENSE` 已是 339 行标准 FSF 文本），并要求源码文件头部带作者签名 `Evil0ctal <evil0ctal1985@gmail.com>` / 年份 2026。

**采纳形态**：Linux kernel / systemd / btrfs-progs 同款两行 SPDX：

```
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
```

**为什么不写完整 GPL boilerplate**：
- 仓库根 `LICENSE` 已有完整 GPLv2 文本，逐文件复述等于 339 行 × N 文件 噪声。
- 与 §7.7 "concise / no fluff" 原则冲突。
- SPDX 标识符是机器可读的标准（[spdx.org](https://spdx.org/licenses/GPL-2.0.html)），github-linguist / scancode / FOSSA 都认。
- Linux kernel 自 2017 年起强制采用，主流 GPL 项目跟进。

**v0.3 全文调整**：
- §7.7.4 改一行：从"文件级 header **不写**"改为"文件级 header **必须写**（详见 §7.8）"。
- §7.7.7 自检表加一项：新建文件带 §7.8 头。
- 新增 **§7.8** 完整章节，6 个子条款：模板（Swift / ObjC / Shell / Python / C）、不加的文件清单、年份策略（首次创建年，不滚动）、多作者扩展、`Scripts/lint.sh` 自动化检查脚本、LICENSE 文件维护规则。
- §4.13 / 4.14 / 4.15 / 4.16 M0 占位代码全部前置 SPDX 两行。
- §6.1 / 6.2 / 6.3 / 6.4 shell 脚本 shebang 后插入 SPDX 两行。
- §5 顶部加注："snippets omit SPDX header for brevity; prepend per §7.8 in actual files"。
- §11 首日 checklist 加一步：`head -3 EvilStore/App/EvilStoreApp.swift` 验证 SPDX 头存在。

**仍未变更**：
- `LICENSE` 不动（标准 GPLv2，SPDX 标识符与之绑定，任何修改会破坏识别）。
- `*.md` / `*.xcconfig` / `*.plist` / `*.xcassets` / `.editorconfig` / `.gitignore` 等不加 header（详见 §7.8.2）。
- 第三方 vendor 源码 `ThirdParty/*` 保留上游原 header。

**Open question（仍未拍板）**：
- §13.8 提到 README 是否立刻补 quickstart：v0.3 仍未做，建议 M0 首个 commit 时一并加，并在末尾加 `## License` 段落引用 LICENSE。

---

> **v0.3 审查重点**（取代旧版）：
> 1. §7.7 消息风格清单 —— 6 条总原则 + 7.7.7 自检表是否还差什么？
> 2. §7.8 文件头模板 —— SPDX + Copyright 两行 OK 吗？要不要加第三行（如项目名 / contact）？
> 3. §7.8.2 不加 header 的文件清单 —— 是否还要补/减？
> 4. §7.8.3 年份策略（首次创建年，不滚动）—— 同意吗？
> 5. §8 测试策略重写 —— "真机 only" 是否还有死角？
> 6. §8.7 E2E 手测清单模板 —— 字段是否够？
> 7. §9 CI build-only 决策 —— 接受吗？
> 8. §13.8 / §13.9 末尾 README quickstart —— 立刻加 / 留到 M5 / 不加？
>
> 审阅完确认就开工 M0。
