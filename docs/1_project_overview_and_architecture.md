# EvilStore — 项目总览与架构设计（1 号文档）

> 版本：**v0.3（引入"借用系统 App Store 会话"为默认登录路径，见 §8）**
> 日期：2026-05-05
> 作者：evil0ctal
> 适用环境：iOS 14.0 beta 2 — 16.6.1 / 16.7 RC / 17.0（与 TrollStore 支持范围一致）
> 上游参考：
> - [`majd/ipatool`](https://github.com/majd/ipatool) — App Store 私有协议客户端（Go，CLI）— 协议第一手参考
> - [`opa334/TrollStore`](https://github.com/opa334/TrollStore) — 永久旁载（permasign）安装器，基于 CoreTrust bug
> - [`Lakr233/Asspp`](https://github.com/Lakr233/Asspp) — Swift/SwiftUI 实现的多账号 App Store 客户端（iOS 17+ / macOS 15+），同协议 GUI 化的成熟参考
> - [`Lakr233/ApplePackage`](https://github.com/Lakr233/ApplePackage) — Asspp 的协议核心，"ipatool rewrite in library and cli using Swift"，**SPM 库，平台 `.iOS(.v15)` / `.macOS(.v12)`**
> - [`dlevi309/ipatool-ios`](https://github.com/dlevi309/ipatool-ios) — 早期 ObjC 移植（Asspp 已停用，但其 iOS 兼容代码仍可借鉴）
>
> ⚠️ **法律与道德边界**：本工具仅用于已购买/已绑定 Apple ID 的合法 App 历史版本下载与本地安装；不得用于绕过付费、分发盗版、或攻击 Apple/第三方账号。所有 App Store 凭据只在本机 Keychain 落盘，不上传任何服务器。
>
> ⚠️ **来自 Asspp 的两条额外安全提醒（已采纳）**：
> 1. **不要使用主 Apple ID** — 私有协议高敏，Apple 一旦风控触发账号封禁，可能导致设备 Activation Lock 不可摘除（Asspp README 引用，未确认但不能赌）。EvilStore UI 必须在登录页强提示。
> 2. **GUID 等同密码** — 设备 GUID 与账号绑定，泄露等于把账号暴露给跨设备追踪。GUID 落盘必须走 Keychain，且日志层屏蔽。

---

## 0. 目标 (One-Liner)

> **EvilStore 是一款 TrollStore 专属 iOS App**：**默认借用系统 App Store 已登录的会话**（无需用户在本应用中再次输入 Apple ID 密码），搜索/查询任意 App 的所有历史版本（External Version ID），下载已购 IPA，自动注入 `iTunesMetadata.plist` 与 `sinf` 票据，再借助 TrollStore 的 CoreTrust bypass 永久安装到本机——把 ipatool 的能力从 PC/Mac 终端搬进 iPhone，并补齐"装回去"那一步。
>
> 当系统未登录 App Store 或会话借用失败时，回退到"手动登录"模式（v0.2 路线，作为兜底）。详见 §8。

### 核心使用场景

1. **降级安装**：当前 App Store 只能下载最新版，EvilStore 可列出所有历史 `softwareVersionExternalIdentifier`，下载指定版本。
2. **取证/逆向**：研究人员需要某个旧版本进行漏洞复现/对比分析，无需 PC。
3. **离线归档**：把已购应用的 IPA 备份到本地（含合法 sinf 授权），便于以后重装。
4. **配合自家工具链**：例如本人 `XHS-DYLIB` 这类需要针对特定版本进行 hook 的项目，可以直接在设备上拉到目标版本即装即用。

---

## 1. 上游项目原理速查

### 1.1 ipatool — App Store 私有 API 协议

ipatool 不依赖 iTunes，直接走 Apple 的私有 storefront API。下面是关键流程，已对照源码核对（`pkg/appstore/*.go`）：

#### 1.1.1 鉴权 (`appstore_login.go` / Asspp `Authenticate.swift`)

> ⚠️ **审计修正**：Asspp/ApplePackage 与 ipatool 在以下几处有微妙差异，且 ApplePackage 的版本是当前仍能跑通 Apple 私有 API 的"较新答案"。EvilStore 以 ApplePackage 实战版为准，ipatool 为备份。

| 项 | 值（以 ApplePackage 为准） |
|---|---|
| Endpoint | 先 `GET https://init.itunes.apple.com/bag.xml` 拉 bag，从中读 `authEndpoint`；附加 `?guid=<GUID>` |
| Method | `POST application/x-apple-plist`（**注意：是 plist payload，不是 form-urlencoded**；ipatool 老版本用 form，但 Apple 现在双格式都收，ApplePackage 用 plist 走得更稳） |
| Payload | `{ appleId, password+code, guid, attempt, rmp:"0", why:"signIn" }` |
| `attempt` 取值 | **不是 ipatool 的递增计数**：无 2FA 时填 `"4"`，带 2FA code 时填 `"2"`（ApplePackage `Authenticate.swift` 实测） |
| 2FA | 6 位 auth code **直接拼接在 password 后面**（`password+code`） |
| Cookies | 必须**在登录间复用**（首次返回的 cookie 后续请求都要带）；persistence 也要包含 cookies，不只是 token |
| 重定向 | 302 + `Location` → 切换到对应 Pod（`pXX-buy...`），最多 3 次 |
| 失败码 | `failureType=5005` = 2FA 码错误；`""` + `customerMessage="MZFinance.BadLogin.Configurator_message"` = 需要 2FA |
| 关键响应字段 | `dsPersonId`（DSID）、`passwordToken`、`accountInfo.{appleId, address.{firstName,lastName}}`、Header `X-Set-Apple-Store-Front`（取首段 storefront ID，如 `143441`）、Header `pod` |

**GUID 策略（v0.2 重大修订）**：
- ApplePackage 的 `DeviceIdentifier.system()` 在 `#if os(iOS)` 分支**直接 throw**（Apple 自 iOS 7 起 MAC 全返 `02:00:00:00:00:00`，不可用）。
- 因此正确做法是 **首次启动 → `DeviceIdentifier.random()` 生成 12 位 hex → 立即落 Keychain → 终生复用**。Asspp `App/main.swift` 在启动时为 `ApplePackage` 注入这个 ID。
- ❌ 不要再用 IDFV：IDFV 在卸载后会变，触发 Apple 的"新设备"风控；Apple 也已知 IDFV 是 vendor-scoped fingerprint。
- 备份与恢复：用户切设备时需要"导出 GUID"功能（一行 hex），否则被风控等于丢账号。

落库到 Keychain 的 `Account` 结构（按 ApplePackage `Models/Account.swift`）：
```text
{
  email, password, appleId,
  store,                       // 5-6 位 storefront 头段，如 "143441"=US
  firstName, lastName,
  passwordToken,
  directoryServicesIdentifier,
  cookie: [Cookie],            // ★ 必须持久化
  pod                          // 可空，影响后续请求 host: p{pod}-buy.itunes.apple.com
}
```

#### 1.1.2 购买 / 领取免费许可 (`appstore_purchase.go`)

```
POST https://p{Pod}-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/buyProduct
Headers:
  Content-Type: application/x-apple-plist
  iCloud-DSID, X-Dsid: <DSID>
  X-Apple-Store-Front: <storefront>
  X-Token: <passwordToken>
Body (binary plist):
  salableAdamId, guid, price=0, productType=C,
  pricingParameters=STDQ (App Store) | GAME (Apple Arcade),
  buyWithoutAuthorization=true, hasAskedToFulfillPreorder=true ...
```

- 仅支持 `Price == 0` 的免费应用；付费应用必须在网页端先购买，本地只发"已购确认"。
- 失败码：`2059`（暂时不可用，重试 GAME pricing）/`5002`（已拥有许可）/`9610`（无许可）/`2034`（token 过期）。

#### 1.1.3 列出历史版本 (`appstore_list_versions.go`)

复用 `volumeStoreDownloadProduct` 端点，不指定 `externalVersionId`。返回的 `Items[0].Metadata` 中：

```text
softwareVersionExternalIdentifier      → 当前最新版本的 external id
softwareVersionExternalIdentifiers[]   → 历史所有 external id（升序）
```

> external id 是 Apple 内部数字 ID，例如 `831776527`，不是 `9.28.1` 这样的语义版本。展示用版本号需要逐个 `download(externalVersionId=...)` 后从 `bundleShortVersionString` 取，或者用 `appstore_get_version_metadata.go` 提供的 **HTTP Range + ZIP 流式解析** 方案：只下 IPA 头部几 MB 就能读 `Info.plist` 的 `CFBundleShortVersionString` 与 `releaseDate`，避免每次完整下载。

#### 1.1.4 下载并打补丁 (`appstore_download.go` + `appstore_replicate_sinf.go` / ApplePackage `SignatureInjector.swift`)

```
POST .../volumeStoreDownloadProduct
Body: { salableAdamId, guid, externalVersionId? }
→ Items[0]: { URL, md5, sinfs:[{id,sinf-bytes}], metadata:{...} }
```

下载完成后客户端做两件**关键的本地补丁**（这正是和官方 App Store 客户端的差异点，少了这步装上去会启动闪退）：

1. **`iTunesMetadata.plist`**：把响应里 `metadata` 写进 IPA 顶层，并补上 `apple-id` / `userName`，让 `installd` 认可这是合法购买的副本。
2. **`sinf` 票据回填**：根据 IPA 内部结构选择策略：
   - 单二进制：写 `Payload/<App>.app/SC_Info/<CFBundleExecutable>.sinf`
   - 多二进制（含 plug-ins / extensions）：解析 `Payload/<App>.app/SC_Info/Manifest.plist` 中的 `SinfPaths[]`，把每条 sinf 对号入座。

> ⚠️ **审计修正：实现策略改用 in-place 追加**
>
> ipatool 的 Go 实现是"原 zip → 复制所有条目到新 zip → 追加新文件"，对几百 MB 的 IPA 是 2× 磁盘 IO，移动设备上很不友好。
>
> **采用 ApplePackage 的方式**：用 `ZIPFoundation` 以 `Archive(url:, accessMode: .update)` 打开 IPA，调 `addEntry(...)` 直接追加 `iTunesMetadata.plist` 与各 `*.sinf` 文件。zip 末尾追加 + 重写 central directory 即可，无需复制整个包。EvilStore 以此为基线实现，移动端体验高一个量级。
>
> 注意：`addEntry` 的 `provider` 闭包按需返回切片字节，**`Sinf.sinf` 字节流必须用 `Data.subdata(in:)` 切片**（原 `Data` 索引基准化的坑见 ApplePackage 实现），否则索引会越界。

#### 1.1.5 Keychain (`pkg/keychain`)

ipatool 用 `99designs/keyring`，把 `account` JSON 落到操作系统 Keychain。在 iOS 端我们直接用 `Security.framework` 的 `kSecClassGenericPassword`，service=`com.evil0ctal.evilstore.account`。

---

### 1.2 TrollStore — 永久旁载机制

TrollStore 利用 AMFI / CoreTrust 在校验"多签名者"二进制时的逻辑漏洞，让 `installd` 把任意带有伪造 root CA 签名的 IPA 当成"系统 App"接受并永久安装。对 EvilStore 而言，关键认知：

#### 1.2.1 我们获得的"超能力"

只要 EvilStore 自身用 TrollStore 安装并带上下面这套 entitlements（参考 `TrollStore/entitlements.plist`），系统就把我们当作"特权用户进程"对待：

```xml
<key>com.apple.private.security.no-sandbox</key><true/>
<key>com.apple.private.persona-mgmt</key><true/>
<key>platform-application</key><true/>
<key>com.apple.security.exception.files.absolute-path.read-write</key>
<array><string>/</string></array>
<key>com.apple.private.MobileContainerManager.allowed</key><true/>
<key>com.apple.private.MobileInstallationHelperService.allowed</key><true/>
<key>com.apple.private.MobileInstallationHelperService.InstallDaemonOpsEnabled</key><true/>
<key>com.apple.lsapplicationworkspace.rebuildappdatabases</key><true/>
<key>com.apple.private.uninstall.deletion</key><true/>
<key>com.apple.private.security.storage.AppDataContainers</key><true/>
```

意味着：
- 整个文件系统读写（包括 `/var/mobile/Media/...` 大文件缓存目录）。
- `posix_spawnattr_set_persona_np(attr, 99, OVERRIDE)` + `set_persona_uid_np(0)` 可以把子进程跑成 **uid 0**。
- 直接调用 `LSApplicationWorkspace`、`MobileInstallationHelperService` 等私有 framework 完成安装/卸载。

#### 1.2.2 三条安装回路（含 Asspp 对照）

> **审计补充**：Asspp 在 iOS 上**不依赖 TrollStore**，走的是 **OTA itms-services + Vapor 本地 HTTPS server + bundle 内置受信任 TLS 证书** 的路径（`Asspp/Backend/Installer/`）。这条路 EvilStore **不采用**——它要求合法签名 + 有效证书 + 用户在 iOS 设置里点"信任"，且 iOS 越新对 itms 越苛刻。我们既然吃 TrollStore 的 entitlements，就直接走更稳的特权安装路径。仅在此记录以避免后续讨论混淆。

EvilStore 拿到合法 IPA 之后，有两种把它装上去的方式：

**A. 通过 TrollStore URL Scheme（推荐 MVP 方案）**

```
apple-magnifier://install?url=file:///var/mobile/Media/EvilStore/Downloads/com.foo.bar_1.2.3.ipa
```

- TrollStore 1.3+ 接管了 `apple-magnifier://`（替换原放大镜应用，避免被 jailbreak 检测扫描到独占 scheme）。
- 不需要 EvilStore 自带 root helper，迭代成本最低。
- 缺点：每次安装都会被 TrollStore 弹一次确认框（除非用户在 TrollStore 设置中关掉），无法做"一键升降级"。

**B. 内嵌 root helper（v2 进阶方案）**

复刻 TrollStore 的 `RootHelper` 二进制流程：
1. 把 `trollstorehelper` 之类的 helper 二进制塞进 EvilStore.app 里，单独 fakesign，带 `com.apple.private.persona-mgmt` 等 ent。
2. App 主进程调用 `spawnRoot(rootHelperPath(), @[@"install", @"custom", ipaPath], ...)`。
3. helper 内部 `extract()`（libarchive）→ ldid 二次签名 → CoreTrust bypass（`coretrust_bug.{c,h}`）→ `installd` 走 `MobileInstallationInstall` → `uicache -p` 刷图标缓存。

V1 阶段我们走 A，并在 v2 借鉴 TrollStore 的 `RootHelper/unarchive.m`、`Shared/TSUtil.m` 写自己的 helper（这部分等真正要做"一键安装"再展开）。

#### 1.2.3 安装时常见错误码（直接从 `TSApplicationsManager.m` 拷贝过来给我们的 UI 用）

| Code | 含义 |
|---|---|
| 166-169 | IPA 文件 / 解压失败 |
| 171 | 同 bundle id 已被非 TrollStore 应用占用 — 可"强制安装" |
| 173 / 175 / 185 | ldid 缺失 / 签名失败 / CoreTrust bypass 失败 |
| 179 | 与系统内建 App 冲突（防 boot loop） |
| 180 | 主二进制仍为加密态（说明 IPA 是从加密设备 dump 的，非 App Store 合法版本） |
| 182 | 装好了但需要打开开发者模式 |
| 184 | 装好了但部分子二进制仍加密（plugins 可能不工作） |

---

## 2. EvilStore 整体架构

### 2.1 分层

```
┌──────────────────────── UI Layer (SwiftUI / UIKit) ────────────────────────┐
│  Search · Detail (含版本时间轴) · Downloads · Library · Settings · Login   │
└──────────┬─────────────────────────────────────────────────────────────────┘
           │ ViewModel (Combine / async-await)
           ▼
┌──────────────────────── Domain / Service Layer ────────────────────────────┐
│  AccountService · CatalogService · DownloadService · InstallService        │
│  VersionResolverService · LogService                                       │
└──────────┬─────────────────────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────── Core (Swift / ObjC++) ─────────────────────────────┐
│  AppStoreClient (login / purchase / list / download)                        │
│  IPAPatcher    (zip-rewrite + iTunesMetadata + sinfs)                       │
│  PartialZipReader (HTTP Range → 流式解析 Info.plist 用于版本号探测)         │
│  KeychainVault (Security.framework)                                         │
│  TrollStoreBridge (apple-magnifier:// + 可选自带 helper)                    │
└──────────┬─────────────────────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────── Platform / TrollStore-only Capability ─────────────────┐
│  Sandbox-bypass entitlements · 全盘读写 · spawnRoot · LSApplicationWorkspace│
└────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 关键模块职责

| 模块 | 语言 | 上游对照 | 核心职责 |
|---|---|---|---|
| **AppStoreClient** | Swift | ipatool `pkg/appstore/*.go` + ApplePackage `Sources/ApplePackage/Commands/*.swift` | 私有 storefront 协议封装：`lookup` / `search` / `purchase` / `listVersions` / `download`。`login` 在 v0.3 退化为 fallback；调用方注入 `Account` 即可，**不关心账号是 stealth 借来的还是用户输入的** |
| **SystemSessionImporter** ⭐ v0.3 新增 | Swift / ObjC | — | 从系统 App Store 借用会话：路径 A `accountsd` (`ACAccountStore`) → 路径 B `/var/mobile/Library/com.apple.itunesstored/` 文件 → 路径 C/D 备用。返回与 `AppStoreClient` 兼容的 `Account` 结构（DSID / passwordToken / cookies / GUID 都来自系统） |
| **AccountManager** | Swift | Asspp `AppStore.swift` | 多账号枚举 / 切换 / 当前活跃账号 / `storefront → countryCode` 映射表。**v0.3 升级**：账号有两类 source — `.systemBorrowed`（来自 `SystemSessionImporter`，密码字段为空）/ `.manual`（来自 v0.2 登录流程，凭据完整）；UI 区分图标 |
| **PlistCoder** | Swift | `PropertyListSerialization` (Foundation 自带) | XML / Binary plist 双向编解码 |
| **PartialZipReader** | Swift | ipatool `appstore_partial_zip.go` | 实现 `HTTPRangeReaderAt` → 拼装最小 zip central directory → 只读 `Info.plist` 获取展示版本号与 releaseDate |
| **IPAPatcher** | Swift | ApplePackage `SignatureInjector.swift`（**直接参考实现**） | `ZIPFoundation` `Archive(.update)` in-place 追加 `iTunesMetadata.plist` + `*.sinf` |
| **BinaryCookiesParser** ⭐ v0.3 新增 | Swift | Apple Binary Cookies v0x100 公开格式 | 解析 `/var/mobile/Library/Cookies/com.apple.itunesstored.binarycookies` 等 cookie jar，转成 `[Cookie]` 喂给 `AppStoreClient` |
| **KeychainVault** | Swift | ipatool `pkg/keychain` / Asspp `KeychainAccess` | `kSecClassGenericPassword`，service `com.evil0ctal.evilstore.<email>`，**支持多账号**（v0.2 升级，对齐 Asspp） |
| **DeviceIdentifier** | Swift | ApplePackage `DeviceIdentifier.swift` | **v0.3 调整**：stealth 模式下从系统读 GUID（`/var/mobile/Library/com.apple.itunesstored/` 内有持久化），与 App Store 共用；fallback 模式才走 `random()` → Keychain |
| **TrollStoreBridge** | Swift / ObjC | `TSInstallationController.m` + URL scheme | v1：`UIApplication.open(URL("apple-magnifier://install?url=..."))`；v2：内嵌 helper |
| **DownloadEngine** | Swift | ipatool `appstore_download.go::downloadFile` / Asspp `Digger` | 支持 `Range: bytes=offset-` 断点续传；并发上限默认 3；进度 `Progress` 桥接到 UI |
| **LogService** | Swift | — | 本地环形 log，方便用户在装失败时一键复制（与 TrollStore 的 "Copy Debug Log" 行为对齐）。**密码 / GUID / cookies / DSID / passwordToken 必须屏蔽**。 |

### 2.3 数据流：典型"装一个旧版本"

```
User 在 Search 输入 "微信"
  └─→ CatalogService.search(term)
        └─→ AppStoreClient.search → iTunes Lookup API（公开接口，不需要登录）
            └─→ 列表展示

User 点击微信 → Detail 页
  └─→ VersionResolverService.fetchHistory(appID)
        ├─→ AppStoreClient.listVersions(account, app)
        │     → softwareVersionExternalIdentifiers[]
        └─→ for each id: PartialZipReader.peek(id) (并发，最多 4)
              → bundleShortVersionString + releaseDate
              → 缓存到本地 SQLite/JSON（key=appID:externalID）

User 选定 "8.0.32" → 点击 Download
  └─→ DownloadService.enqueue(app, externalID)
        └─→ AppStoreClient.purchase(if no license) [免费应用静默领许可]
        └─→ AppStoreClient.download(externalID) → tmp .ipa
        └─→ IPAPatcher.injectMetadata + injectSinfs → final .ipa
        └─→ 写入 /var/mobile/Media/EvilStore/Downloads/

下载完成 → 用户点击 Install
  └─→ TrollStoreBridge.install(ipaURL)
        └─→ open("apple-magnifier://install?url=<file>")
        └─→ TrollStore 接管，完成 ldid 重签 + CoreTrust bypass + installd
```

### 2.4 鉴权与凭据安全

- 密码**绝不**写入 NSUserDefaults / 沙箱 plist；只持久化在 Keychain 的同一条 generic password 中。
- 2FA：UI 弹 6 位输入框，拼接到 password 后重新走 login。
- 失败重试：捕获 `passwordTokenExpired (2034)` → 自动用持久化密码重新走一次 login，重新拿 `passwordToken`，对用户透明。
- "退出登录"：调用 `KeychainVault.delete()`，等同 ipatool 的 `auth revoke`。

### 2.5 与 TrollStore 协同的工程边界

- **Bundle Identifier**：建议 `com.evil0ctal.evilstore`，**不要**与系统内建 App 冲突（避开 codes 179）。
- **Entitlements**：直接复用 TrollStore 那套（见上文），但不需要 `MobileInstallationHelperService.*` 的全集——v1 只把"装"这件事委托回 TrollStore，所以最小集合可以是：
  ```
  com.apple.private.security.no-sandbox
  platform-application
  com.apple.security.exception.files.absolute-path.read-write = ["/"]
  com.apple.private.persona-mgmt   (v2 自带 helper 时必需)
  ```
- **打包**：`Makefile` + theos（与 TrollStore 同套），输出 `EvilStore.tipa`，由 TrollStore 安装。
- **签名**：`ldid -S<entitlements.plist> Payload/EvilStore.app/EvilStore`，CI 里跑。

### 2.6 iOS 14+ 兼容矩阵（v0.2 新增）

> Asspp 的 deployment target 是 iOS 17，ApplePackage 是 iOS 15。本项目要降到 **iOS 14.0**，必须显式列出"哪些技术能用、哪些得替换"。

| 项 | iOS 14 baseline | Asspp/ApplePackage 用法 | EvilStore 决策 |
|---|---|---|---|
| **Swift Concurrency** (`async`/`await`/`Task`/`actor`/`@MainActor`) | ✅ 通过 Xcode 13.2+ 的 back-deployed concurrency runtime | 大量使用 | **采用**（Xcode 14+ 自动 backwards-deployment） |
| **`@Observable` macro** | ❌ iOS 17+ 才有（依赖 Observation framework） | Asspp 全用 | **不用**，回退到 `ObservableObject` + `@Published` |
| **`NavigationStack`** | ❌ iOS 16+ | Asspp `NavigationSplitView` (macOS) / `TabView` (iOS) | 用 iOS 14 的 `NavigationView` + programmatic push |
| **`.searchable`** | ❌ iOS 15+ | Asspp Search 页 | 自己写 `UISearchBar` UIViewRepresentable |
| **`AsyncImage`** | ❌ iOS 15+ | Asspp 用 Kingfisher | **采用 Kingfisher**（iOS 12+） |
| **`async-http-client` (NIO)** | ⚠️ 库可用，但 NIO 在低 iOS 上未广泛验证 | ApplePackage 全部 HTTP 走 NIO | **替换为 `URLSession`** + `HTTPCookieStorage` |
| **`ZIPFoundation`** | ✅ 支持 iOS 12+ | ApplePackage 用 | **采用** |
| **`PropertyListSerialization`** | ✅ Foundation 自带 | ApplePackage 用 | **采用**（替代 ipatool 的 `howett.net/plist`） |
| **`Vapor` HTTPS server (OTA install)** | ❌ 不需要 | Asspp 用于 itms-services 安装 | **删掉**整条 Installer 子系统，TrollStore 专属 |
| **SwiftUI App lifecycle** | ✅ iOS 14+ | Asspp 用 | **采用**，保留 `UIApplicationDelegateAdaptor` 处理 URL scheme |

**编译目标策略**：
- `IPHONEOS_DEPLOYMENT_TARGET = 14.0`（硬底线）
- 内部用 `if #available(iOS 15, *) { ... } else { ... }` 渐进增强；UI 在 14 上"能用"，在 15+ 上更顺手。
- 不引入 `@Observable` / `NavigationStack` 这种 iOS 17+ 独占语法（即便用 `@available` 包裹也会污染整体设计——直接禁用更干净）。

**TrollStore 用户的 iOS 分布参考**：CoreTrust bug 影响 iOS 14.0 beta 2 ~ 17.0，主流社区集中在 iOS 14.x / 15.x / 16.x；选 14.0 作为 floor 能覆盖最早一批"我专门为留 jailbreak/TrollStore 不升级"的设备。

### 2.7 是否复用 ApplePackage SPM 库？（v0.2 新增）

ApplePackage 已经把 ipatool 协议层用 Swift 实现一遍，看似可以直接 `dependencies: [.package(url: "...ApplePackage.git")]` 拉来用。但有几个硬约束：

1. **deployment target 不匹配**：ApplePackage 是 `.iOS(.v15)`，且依赖 `async-http-client`（NIO 链路）。把 minimum 降到 14 + 切到 URLSession 改动量等于"重写一半"。
2. **theos 工程对 SPM 的支持薄**：TrollStore 生态用 theos `Makefile` 而非 xcodebuild，SPM 包要么手工脚本拉源码 vendoring，要么单开 xcframework，工程化成本不低。
3. **风控敏感**：协议字段说不准什么时候被 Apple 改，我们要能即时改 endpoint / payload，自家代码改起来更顺手；用上游库则要发 PR 等合入。

**决策**：**不直接 SPM 引入，但作为 vendor 源码参考。** 把 ApplePackage 的关键 `.swift` 文件（`Authenticate.swift` / `Download.swift` / `VersionFinder.swift` / `Lookup.swift` / `Search.swift` / `SignatureInjector.swift` / `Bag.swift`）作为蓝本，重写成 URLSession + iOS 14 兼容版本，放进 `Core/AppStoreClient/`。原文件保留在 `ThirdParty/ApplePackage-reference/` 仅供查阅与升级合并（带原始 commit hash + license 标注）。

---

## 3. 项目目录结构（v1 规划）

> 我会在后续 2 号文档里把这套结构落地成空文件骨架；本节只先达成一致。

```
EvilStore/
├── README.md
├── LICENSE
├── docs/
│   ├── 1_project_overview_and_architecture.md      ← 当前这份
│   ├── 2_directory_skeleton_and_build.md           ← 待写：目录骨架 + theos/Makefile
│   ├── 3_appstore_protocol_reference.md            ← 待写：私有协议详细字段表
│   ├── 4_ipa_patching_and_install_pipeline.md      ← 待写：补丁与安装流水线
│   └── 5_security_and_compliance.md                ← 待写：合规与威胁模型
│
├── EvilStore/                              # 主 App target（theos application）
│   ├── Makefile
│   ├── control                             # deb 元数据
│   ├── entitlements.plist
│   ├── Info.plist
│   ├── Resources/
│   │   ├── Assets.xcassets                 # 图标 / 主题
│   │   └── Localizable.strings
│   ├── Sources/
│   │   ├── App/
│   │   │   ├── ESAppDelegate.swift
│   │   │   ├── ESSceneDelegate.swift
│   │   │   └── ESRouter.swift              # 处理 apple-magnifier://evilstore-* 自定义子 path
│   │   ├── UI/
│   │   │   ├── Search/                     # SearchView + ViewModel
│   │   │   ├── Detail/                     # AppDetailView（版本时间轴）
│   │   │   ├── Downloads/                  # 下载队列
│   │   │   ├── Library/                    # 已下载 IPA
│   │   │   ├── Settings/                   # 账户 / 安装方式 / 路径
│   │   │   └── Common/                     # 通用组件、错误 alert
│   │   ├── Domain/
│   │   │   ├── Models/                     # Account / App / Version / Sinf / IPAArtifact
│   │   │   ├── AccountService.swift
│   │   │   ├── CatalogService.swift
│   │   │   ├── VersionResolverService.swift
│   │   │   ├── DownloadService.swift
│   │   │   └── InstallService.swift
│   │   ├── Core/
│   │   │   ├── AppStoreClient/             # Swift
│   │   │   │   ├── AppStoreClient.swift
│   │   │   │   ├── Endpoints.swift         # 对应 ipatool/constants.go
│   │   │   │   ├── Login.swift
│   │   │   │   ├── Purchase.swift
│   │   │   │   ├── ListVersions.swift
│   │   │   │   ├── Download.swift
│   │   │   │   ├── Search.swift
│   │   │   │   └── Lookup.swift
│   │   │   ├── HTTP/
│   │   │   │   ├── HTTPClient.swift        # URLSession 封装 + cookie jar
│   │   │   │   └── XMLPlistPayload.swift
│   │   │   ├── Plist/
│   │   │   │   └── PlistCoder.swift
│   │   │   ├── Zip/
│   │   │   │   ├── IPAPatcher.swift        # 复制 zip + 注入 metadata/sinf
│   │   │   │   └── PartialZipReader.swift  # HTTP Range 流式 zip
│   │   │   ├── Keychain/
│   │   │   │   └── KeychainVault.swift
│   │   │   ├── Device/
│   │   │   │   └── DeviceFingerprint.{m,h} # IDFV → GUID 派生
│   │   │   └── TrollStore/
│   │   │       ├── TrollStoreBridge.swift  # URL scheme 调用 + 状态回调
│   │   │       └── TSErrorCatalog.swift    # code → 文案
│   │   └── Util/
│   │       ├── Logger.swift
│   │       └── FileLayout.swift            # /var/mobile/Media/EvilStore/{Downloads,Cache,Logs}
│
├── EvilStoreHelper/                        # v2 才启用：root helper
│   ├── Makefile
│   ├── control
│   ├── entitlements.plist                  # com.apple.private.persona-mgmt + ...
│   └── Sources/
│       ├── main.m
│       ├── unarchive.{m,h}                 # libarchive 解压（参考 TrollStore RootHelper）
│       ├── ldid_invoke.{m,h}               # 调 /var/jb/usr/bin/ldid 或内嵌静态版
│       └── coretrust_bypass.{c,h}          # 端口自 TrollStore Exploits/fastPathSign
│
├── ThirdParty/
│   ├── ZIPFoundation/                      # MIT，纯 Swift zip
│   ├── libarchive/                         # 仅 helper 用
│   └── README.md                           # 列每个依赖的来源 + 许可
│
├── Scripts/
│   ├── build_tipa.sh                       # theos 构建 + ldid 签名 + 打包 .tipa
│   ├── ci_lint.sh
│   └── bump_version.sh
│
├── Tests/
│   ├── AppStoreClientTests/                # 录制响应 plist 做 mock
│   ├── IPAPatcherTests/                    # 用一个最小 IPA fixture 测 sinf 注入
│   ├── PartialZipReaderTests/
│   └── Fixtures/
│       ├── login_success.plist
│       ├── login_2fa_required.plist
│       ├── list_versions_response.plist
│       └── tiny_app.ipa                    # 几 KB 的占位 IPA
│
└── .github/
    └── workflows/
        ├── build.yml                       # theos build + 上传 .tipa artifact
        └── lint.yml                        # swiftlint / clang-format
```

**布局原则**（与 `~/.claude/rules/common/coding-style.md` 一致）：
- 每个文件 ≤ 400 行；按特性切目录（Search/Detail/Downloads…），不按类型一锅炖。
- `Core/` 之下是不依赖 UIKit/SwiftUI 的纯逻辑层，单独成模块也能跑命令行测试。
- 第三方代码进 `ThirdParty/`，每个子目录带 README 标明 license 与上游 commit。

---

## 4. 路线图（Milestones）

> ⚠️ **v0.3 重排**：登录路径从单一"内置登录"改为"stealth 优先 + manual 兜底"。M0.5 是新增的 PoC 阶段，必须先验证私有 entitlement 与 `accountsd` 接口在 iOS 14/15/16/17 上各能拿到什么，再决定 stealth 是否能成为默认路径。如果 PoC 失败，回退到 v0.2 路线（M1 直接做 manual 登录）。

| Milestone | 范围 | 验收标准 |
|---|---|---|
| **M0 — 骨架** | 目录结构 + theos build pass + 空 UI | TrollStore 能装上 EvilStore.tipa，启动后看到一个空 TabBar |
| **M0.5 — Stealth PoC** ⭐ v0.3 新增 | 4 条会话借用路径逐一实测；输出"哪条在 iOS 14/15/16/17 各跑通"的兼容矩阵 | 至少在 **一个 iOS 主线版本**上能从系统读出可用的 `{ DSID, passwordToken, cookies, GUID }`，且发一个 `lookup` 不需要再登录 |
| **M1 — Stealth + Manual 双模式登录** | `SystemSessionImporter`（M0.5 选定的最稳路径）+ v0.2 的 manual 登录作 fallback；`AccountManager` 多账号；`search` / `lookup` | (a) 设备已登录 App Store → EvilStore 启动后零密码；(b) 未登录 → 弹 manual 流程；(c) 两种来源混用时 UI 区分清楚 |
| **M2 — 版本列表** | `listVersions` + `PartialZipReader` 探测每版 `bundleShortVersionString` | 在某个常用 App 上列出 ≥10 个历史版本，含人类可读版本号与发布时间 |
| **M3 — 下载与补丁** | `purchase` / `download` / `IPAPatcher`（metadata + sinf） | 拉一个免费 App 旧版，落地的 .ipa 用 `unzip -l` 能看到 `iTunesMetadata.plist` 和 `SC_Info/*.sinf` |
| **M4 — 安装回环（URL scheme）** | `TrollStoreBridge` 调 `apple-magnifier://install?url=` | EvilStore 内一键装上刚下完的 IPA，桌面出现图标，可启动 |
| **M5 — 体验打磨** | 进度条、错误码文案、断点续传、下载队列、日志导出、stealth 会话过期检测 | 失败可 "Copy Debug Log"；杀进程后续传；`passwordToken` 过期能引导用户回系统设置刷新 |
| **M6 — 内嵌 helper（可选）** | `EvilStoreHelper` 复刻 TrollStore install 路径 | 不弹 TrollStore 确认框直接装；error code 与官方表对齐 |

---

## 5. 风险与开放问题（v0.3 重新评估）

1. **Apple 风控（仍是最高优先级，但风险面变了）**：协议被收紧的事实没变，但 v0.3 的 stealth 模式让请求"看起来像 App Store 自己发的"——同 GUID、同 cookies、同 DSID。**真正的剩余风险点**：
   - User-Agent / TLS JA3 / Header 顺序仿不到 100% 像 App Store（参考 §8.4）。
   - 请求节奏：App Store 一般每天少量 lookup/list，EvilStore 用户可能短时高频探测多版本。需要在 `AppStoreClient` 层加 **请求节流**（默认 ≥500ms 间隔）。
   - 协议字段未来可能再被改：所有 endpoint / payload key 仍收敛在 `Core/AppStoreClient/Endpoints.swift` 单文件，预留"远程 JSON 补丁"开关。
2. **GUID 风控（v0.3 大幅缓解）**：stealth 模式下 GUID 来自系统，与 App Store 共用，新设备风控直接消失。fallback 模式才走"首启 random → Keychain 持久化"路径，并提供导出/导入。
3. **不要用主 Apple ID**（**v0.3 风险下降但仍保留警告**）：默认 stealth 模式下用户根本不"在 EvilStore 输密码"，账号被记录的姿态与日常使用 App Store 一样，封号概率显著下降；但**仍提示**"建议副号"，因为：
   - 协议本身就是私有的，Apple 一旦决定打击使用此协议的客户端，仍会扫到我们。
   - fallback 模式下完全等同 v0.2 风险。
4. **Stealth 会话过期 / 失效**（⭐ v0.3 新增）：
   - `passwordToken` 寿命未知（社区观察 ~7 天），过期后 stealth 模式不能用密码 rotate（我们没有密码）。
   - 处理：检测到 `failureType=2034` 时引导用户回**系统设置 → Apple ID** 重新登录，10 秒后回 EvilStore 自动重读会话。
   - 极端情况：用户已退出系统 App Store，stealth 路径全失败 → 透明降级到 manual 模式。
5. **私有 entitlement 兼容性**（⭐ v0.3 新增）：`com.apple.accounts.appleaccount.fullaccess` / `com.apple.private.accounts.bundleidspoofing` / 通配 keychain ent 在不同 iOS 版本上行为不一，**M0.5 PoC 必须实测**。如果 iOS 17 上路径 A、B 全不可达，stealth 模式不能作为默认。
6. **付费 App**：v1 不支持购买，只能在网页/官方 App Store 已买的前提下下载历史版本——这点必须在 UI 明确告诉用户。Stealth 模式下用户的"已购列表"可以从系统会话直接读，体验比 manual 模式更顺。
7. **CoreTrust 后续修复**：本项目本质依赖 TrollStore 工作，如果 iOS 17.0.1+ 永久封死，受众会快速萎缩；可考虑把 `AppStoreClient` 抽成独立可复用 library，至少 macOS/CLI 也能用。
8. **合规审计**：从沙箱外读写整个文件系统、读 Apple ID 账户信息都是高敏行为。UI 必须：
   - 首次启动显式提示"将读取系统已登录 Apple ID 信息用于下载，不会上传任何服务器"。
   - 在 Settings 提供"清除本地缓存的会话副本"按钮（即便 stealth 模式我们也会在内存/临时缓存里持有 token 几分钟）。
   - **绝不**做任何后台/被动写入或网络请求。
9. **iOS 14 SwiftUI 限制**：`@Observable` / `NavigationStack` / `.searchable` / `AsyncImage` 都没有，UI 实现成本比 Asspp 略高。建议在 §2.6 矩阵基础上保持单一 baseline，不做"按 iOS 版本切换两套 UI 渲染树"的复杂分支——会成为后续维护噩梦。

---

## 6. 参考资料

- ipatool 源码：`pkg/appstore/{login,purchase,list_versions,download,replicate_sinf,partial_zip}.go`
- ipatool 常量：`pkg/appstore/constants.go`
- TrollStore 入口：`TrollStore/{TSAppDelegate,TSInstallationController,TSApplicationsManager}.m`
- TrollStore Root helper：`RootHelper/{main,unarchive,uicache}.m`
- TrollStore 共享工具：`Shared/TSUtil.m`（重点看 `spawnRoot` 实现）
- TrollStore 权限模板：`TrollStore/entitlements.plist`
- ApplePackage 协议层：`Sources/ApplePackage/{Commands,Configuration,Models,Supplement}/*.swift`
  - 重点：`Commands/Authenticate.swift` / `Download.swift` / `VersionFinder.swift` / `Lookup.swift` / `Bag.swift`
  - `Supplement/SignatureInjector.swift`（ZIPFoundation in-place 注入）
  - `Configuration/DeviceIdentifier.swift`（GUID 策略说明）
- Asspp 集成示例：`Asspp/Backend/{AppStore,Downloader,Installer}/*.swift`（仅参考结构与命名，不照抄 iOS 17+ API）
- worthdoingbadly: [The CoreTrust bug write-up](https://worthdoingbadly.com/coretrust/)
- Fugu15 Presentation（YouTube）— 第二个 CoreTrust bug 公开披露

---

## 7. 审计变更记录（v0.1 → v0.3）

> 本节是与 v0.1 的差异说明，便于 review 时聚焦"哪里改了，为什么改"。

### 7.1 新增上游参考

引入 `Lakr233/Asspp`（GUI 版同协议客户端）与 `Lakr233/ApplePackage`（ipatool 的 Swift 重写）作为协议层第一手参考。Asspp 在 GitHub 4.8k 星，已是社区当前最活跃的 ipatool GUI 化方案——其代码反映 **Apple 私有 API 在 2024-2025 年仍然能跑通的最新姿势**，比 ipatool 的 Go 实现更新一些（ipatool 主分支节奏较慢）。

### 7.2 协议层修订

| v0.1（按 ipatool） | v0.2（按 ApplePackage 实测） | 原因 |
|---|---|---|
| `Content-Type: application/x-www-form-urlencoded` | `application/x-apple-plist`（XML plist） | Apple 现在双格式都收，但 ApplePackage 用 plist 走得更稳（与 download/listVersions 同 content-type，简化客户端） |
| `attempt` 递增计数（1→4） | 无 2FA = `"4"`；带 2FA code = `"2"` | ApplePackage 实测值，与 Apple 当前后端期望对齐 |
| 未提及 cookies | **必须持久化 cookies 并随后续请求带回** | Apple 后端把 device-account 绑定写在 cookie 里；不带等于每次新会话 |
| 未提及 `failureType=5005` | 显式映射"2FA 码错误" | UX：从"未知失败"升级为"验证码错了，请重新输入" |

### 7.3 GUID 策略重写

v0.1 写的是"`IDFV` 派生"——错。

修正后：
- ApplePackage `DeviceIdentifier.system()` 在 iOS 上**直接 throw**（已确认 iOS MAC 全返 02:00:...）。
- 正确做法：**首启 `random()` 生成 12-hex → 立即 Keychain 持久化 → 终生只读**。
- 必须提供"导出/导入 GUID"用户操作（一行 hex），让用户跨设备迁移时不丢账号上下文。
- GUID 在日志/截屏/分享面板都需脱敏。

### 7.4 IPA 打补丁实现切换

v0.1：参考 ipatool 的"复制整个 zip 到新 zip + 追加"方案。
v0.2：改用 ApplePackage 的 **`ZIPFoundation` `Archive(accessMode: .update)`** 直接 in-place 追加。
- 移动设备上节省 1× IPA 大小的临时空间，且免去最终 `Rename` 步骤。
- `addEntry(provider:)` 闭包按 position+size 切片返回，**注意必须用 `Data.subdata(in:)`** 处理索引基（ApplePackage 实现已有正确写法可借鉴）。

### 7.5 安装路径选型澄清

Asspp 在 iOS 上走 OTA `itms-services://` + Vapor 本地 HTTPS 服务（带预置 `localhost.qaq.wiki` 受信 TLS 证书）。这条路 EvilStore 主动放弃：
- 要求设备已"信任"该证书（用户操作多）。
- iOS 越新对 itms 越严苛（17+ 已要求各种额外校验）。
- 我们既然吃 TrollStore 的 entitlements，直接走 `apple-magnifier://install?url=...`（v1）→ 自带 root helper（v2）就够了。

§1.2.2 已加注，避免后续被人再提出"为什么不抄 Asspp 的 Vapor"。

### 7.6 多账号支持纳入 v1

v0.1 只设计了单账号 Keychain 落盘。Asspp 的核心卖点之一就是多账号 + 多区域切换；从存储成本看，多账号几乎是零额外代价（Keychain 多条记录），却能解决"美区下美区限定 App、日区下日区 App"的真实痛点。

v0.2 调整：
- `KeychainVault` 的 service 由 `com.evil0ctal.evilstore.account` 升级为 `com.evil0ctal.evilstore.<email>`，配合一个 index 列表存储所有已登录账号。
- 新增 `AccountManager` 模块负责账号枚举、切换、当前活跃账号、`storefront → countryCode` 映射（如 `143441 → "US"`、`143465 → "JP"`、`143473 → "CN"` …）。
- UI Settings 页给出账号切换器，列表展示 email + storefront flag。

### 7.7 iOS 14+ 兼容矩阵（§2.6）

v0.1 没明确 iOS 14 上 SwiftUI / 并发 / HTTP 栈各自的能用情况。v0.2 显式列表（见 §2.6），关键决策：
- **Deployment target = iOS 14.0**
- **HTTP 栈用 `URLSession`**（不引 NIO / async-http-client）
- **UI 用 `ObservableObject` + `NavigationView`**（不用 iOS 17 的 `@Observable` 与 iOS 16 的 `NavigationStack`）
- **不引 Vapor**

### 7.8 ApplePackage 引入方式（§2.7）

不直接 SPM 依赖，改为 **vendor 源码参考重写**。理由：deployment target 不匹配 + theos 工程对 SPM 支持薄 + 协议风控敏感需要快改。原始文件作为只读参考保留在 `ThirdParty/ApplePackage-reference/`，方便后续上游升级时合并。

### 7.9 风险章节扩充

新增 3 项风险：
- Apple 协议在 2024-2025 已被收紧多次，提供"远程 endpoint 补丁"开关。
- 强制提示"不要用主 Apple ID"。
- iOS 14 SwiftUI 能力不足，禁止"按版本分两套 UI 树"的复杂方案。

### 7.10 仍需后续讨论

- **付费 App 是否支持续购确认（不是新购）**：如果用户已在网页买过，listVersions/download 应能直接拿到许可。需要在 §3 的 4_ipa_patching_and_install_pipeline.md 里覆盖 `licenseAlreadyExists` 的处理路径。
- **是否抽出 `AppStoreClient` 为独立 SPM 包**：长期看是好事（macOS CLI / 其他 GUI 都能用），但 v1 先聚焦 iOS App，统一 vendor 在 monorepo 内。
- **Country/Storefront 映射表的维护**：Apple 不公开这张表，社区版本（如 `iTunes-Storefront-IDs.plist`）会过期。是否进项目自带一个 fallback list，并允许从 GitHub 在线更新？

### 7.11 v0.2 → v0.3 — 引入"借用系统会话"为默认登录路径

**触发讨论**：用户提出"既然 EvilStore 装在已登录 App Store 的系统上，能否像 AppStore++ 一样直接复用现有会话，避免本应用二次登录引起的风控"。

**调研结论（详见 §8）**：
- 真正"hook 系统 App Store"在纯 TrollStore 上**不成立**（TrollStore README 已点明缺 `TF_PLATFORM` + PAC bypass + PMAP trust level bypass）。
- 社区 `CokePokes/AppStorePlus-TrollStore` 自称 "tweak"，实测就是个独立 IPA，跟 EvilStore 同一形态。
- 但用户的真实诉求"零密码输入 + 不触发新设备风控"是可解的——通过**借用系统已建立的 storefront 会话**（DSID / passwordToken / cookies / GUID 来自系统）。

**采纳决策**：
1. v0.3 主路径：**Stealth 模式**，借用系统会话。优先级：路径 A `accountsd` (`ACAccountStore`) → 路径 B 文件系统 → 路径 C/D 备用。
2. v0.2 主路径降级为 **Manual fallback**，仅在 stealth 全失败时启用，不删除（覆盖"系统未登录 App Store"的极少数用户）。
3. 私有 entitlements（`com.apple.accounts.appleaccount.fullaccess` 等）在 PoC 阶段（M0.5）实测后再加进 `entitlements.plist`，文档先规划。
4. 新增 M0.5 milestone，作为整个 v0.3 路线的硬门槛——PoC 失败则回退 v0.2 路线。

**联动改动**：
- §0 TL;DR：默认 stealth，manual 兜底。
- §2.2：新增 `SystemSessionImporter` 与 `BinaryCookiesParser` 模块；`AccountManager` 升级为账号双源（`.systemBorrowed` / `.manual`）；`DeviceIdentifier` stealth 下从系统读 GUID。
- §4：插入 M0.5（Stealth PoC）；M1 改为"Stealth + Manual 双模式登录"。
- §5：风险重排——主 Apple ID 风险下降、GUID 风险大幅缓解；新增 stealth 会话过期、私有 ent 兼容性两条新风险。
- §8：完整章节展开技术原理与四条路径细节。

**仍需 PoC 验证（M0.5 输出物）**：
1. 路径 A 的 `ACAccountStore` 在 iOS 14 / 15 / 16 / 17 上各能拿到什么字段（DSID? AltDSID? token?）。
2. 路径 B 文件 `/var/mobile/Library/com.apple.itunesstored/` 各文件结构是否在 iOS 版本间漂移。
3. `Cookies/com.apple.itunesstored.binarycookies` 解析后的 cookie 直接喂给 storefront API 是否被 Apple 接受（关键：是否需要 cookie expiry 重整）。
4. 全部失败时，manual 模式的密码输入 + 用户当前 GUID（系统读到的）组合，是否仍能正常登录（验证我们能从 stealth 信息里只取 GUID 不取 token，最大化 fallback 体验）。

---

## 8. v0.3 设计候选 — 借用系统 App Store 会话（**默认路径**）

> 本章是 v0.3 引入的核心架构调整。读完本节再看 §2 的模块表与 §4 的 M0.5 / M1，整条线就连贯了。

### 8.1 目标与边界

**目标**：用户在 EvilStore 中**完全不需要输入 Apple ID 密码**，应用能直接代表用户向 storefront API 发 `lookup / search / listVersions / purchase / download`，且 Apple 后端把这些请求识别为"该用户的同一台设备"，不触发新设备登录风控。

**边界（明确不做的事）**：
- ❌ 不在进程内 hook 系统 App Store（TrollStore 不允许，已论证）。
- ❌ 不替换 `/Applications/AppStore.app` 系统二进制（变砖风险）。
- ❌ 不在 stealth 模式下持久化用户密码（我们根本拿不到也不需要）。

**仍要做的兜底**：用户系统未登录 App Store 时，UI 引导其先去**系统设置 → Apple ID** 登录，或选择 manual 登录。

### 8.2 四条会话借用路径

按可靠性 + 维护成本排序，**M0.5 PoC 后再决定哪条作主路径**。

#### 路径 A — `accountsd` 私有 framework（计划主路径）

```objc
@import Accounts;

ACAccountStore *store = [[ACAccountStore alloc] init];
ACAccountType *appleIDType = [store accountTypeWithAccountTypeIdentifier:
                              @"com.apple.account.AppleAccount"];
NSArray<ACAccount *> *accounts = [store accountsWithAccountType:appleIDType];

for (ACAccount *acc in accounts) {
    NSLog(@"username: %@", acc.username);                 // appleId email
    NSLog(@"identifier: %@", acc.identifier);
    NSDictionary *props = [acc valueForKey:@"properties"]; // 含 DSID / AltDSID
    ACAccountCredential *cred = acc.credential;            // oauthToken 在这里
}
```

**所需 entitlements**（TrollStore 全部能授）：
```xml
<key>com.apple.accounts.appleaccount.fullaccess</key>      <true/>
<key>com.apple.private.accounts.bundleidspoofing</key>      <true/>  <!-- 部分 iOS 版本读 token 时需要 -->
```

**优势**：与系统设置 → Apple ID 用同一接口，跨 iOS 版本相对稳定；不依赖文件路径硬编码。

**风险**：
- 私有 framework 接口签名跨版本会微调（用 `valueForKey:` + KVC 取属性，比直接 link header 抗变化）。
- iOS 17+ 对私有 ent 的运行时校验更严，**M0.5 必须实测**。

#### 路径 B — 文件系统读 storeaccountd 状态（fallback）

借助 `com.apple.security.exception.files.absolute-path.read-write = ["/"]`，直接读：

```
/var/mobile/Library/com.apple.itunesstored/
    ├── accountInfo                         ← plist：DSID / email / storefront / GUID
    ├── accountTokens                       ← plist：passwordToken（部分版本加密）
    └── lastKnownStorefronts                ← 区域历史

/var/mobile/Library/Cookies/
    └── com.apple.itunesstored.binarycookies   ← Apple Binary Cookies v0x100，公开格式
```

**Cookie 解析**（`BinaryCookiesParser` 模块负责）：
- Magic 4 bytes: `cook` (`0x636f6f6b`)
- 后续 Page count + Page offsets + 每页 cookie 列表
- 已有多个开源参考实现（GitHub 搜 "binarycookies parser swift"）

**优势**：完全避开私有 entitlement，仅靠 TrollStore 的全盘读权限即可。

**风险**：
- Apple 在不同 iOS 版本可能调整文件结构（M0.5 必须做 14/15/16/17 四版本对照）。
- `passwordToken` 在某些版本上需要 keybag 解密 → 走不通时降级为"只读 GUID + cookies + DSID"，token 缺失时让 storefront 服务端用 cookie 续会话（`listVersions` 实测可行，`download` 视情况）。

#### 路径 C — Keychain 越组读取（高敏，不优先）

```xml
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
```

iOS 16+ 收紧严重，**仅作最后兜底**。如果路径 A 与 B 都失败再考虑。

#### 路径 D — XPC 直接调 storeaccountd（架构最干净，但维护成本最高）

`storeaccountd` 通过 mach service `com.apple.storeaccountd` / `com.apple.storeagent` 暴露"取当前活跃账号"的私有 XPC 接口。系统设置就是这么取账号信息的。

**不优先**：XPC 接口签名跨 iOS 版本会变，每次升级都要重新逆向；ROI 不如路径 A。

### 8.3 双模式状态机

```
              ┌──────────── App 启动 ────────────┐
              │                                    │
              ▼                                    ▼
   ┌────────────────────┐              ┌──────────────────────┐
   │  SystemSession     │              │  Keychain 已有 manual │
   │  Importer 探测     │              │  账号？               │
   └──────────┬─────────┘              └──────────┬───────────┘
              │                                    │
   ┌──────────▼─────────┐               ┌──────────▼───────────┐
   │ A.accountsd 成功？ │               │ 显示账号选择器        │
   └──────┬──────┬──────┘               │ (system + manual)    │
          ✅     ❌                      └──────────────────────┘
          │     │
          │     ▼
          │   ┌──────────────────┐
          │   │ B.文件系统成功？ │
          │   └────┬─────────┬───┘
          │       ✅         ❌
          │       │          │
          │       ▼          ▼
          │   存为          引导用户：
          │ "system        ┌─ 去系统设置登录 App Store
          │  borrowed"     └─ 或在 EvilStore 内 manual 登录
          ▼     │                 │
   AccountManager.activate         ▼
          │                  AppStoreClient.login (v0.2 老路径)
          ▼                        │
   AppStoreClient                  └──→ 存为 ".manual"
   (lookup / list / download)
```

### 8.4 风控对比表

| 信号 | manual 模式（v0.2） | stealth 模式（v0.3） | App Store 本体 |
|---|---|---|---|
| GUID | EvilStore 自生成（random hex） | 与 App Store 共用（来自系统） | 系统分配 |
| DSID | 通过 manual login 拿到 | 直接读系统 | 系统持有 |
| passwordToken | login 拿到 | 直接读系统 | 系统持有 |
| Cookies | EvilStore 独立 cookie jar | 共用 itunesstored cookies | 共用 |
| User-Agent | `EvilStore/1.0 ...` 或仿 `Configurator/2.0` | 同左（仍仿不像真 App Store） | `App Store/x.y` |
| TLS JA3 | URLSession 默认指纹 | 同左 | iTunes/Configurator 指纹 |
| 请求频率 | 用户操作驱动 | 同左（可叠加节流） | 偶发 |
| **Apple 风控视角** | 🔴 新设备 / 新会话 | 🟢 同设备同会话 | ⚪️ 真身 |

剩余风险面（即便 stealth）：UA + JA3 + Header 顺序仿不到 100% App Store。社区数年实践显示**当前不构成大面积封号**，但 Apple 任何时候可以把这些纳入风控。**§5.1 已明确请求节流为必备防御**。

### 8.5 工程接口规范

```swift
// Core/SystemSession/SystemSessionImporter.swift
public protocol SystemSessionImporter {
    /// 检查系统是否已登录 App Store。不抛错，仅返回是否可借用。
    func isAvailable() async -> Bool

    /// 借用一份会话快照。失败时抛具体的 SystemSessionError。
    /// 调用方拿到的 Account 与 Authenticator.authenticate 返回的结构兼容。
    func snapshot() async throws -> Account
}

public enum SystemSessionError: Error {
    case notLoggedIn
    case entitlementDenied(String)        // 路径 A 私有 ent 被拒
    case fileFormatChanged(path: String)  // 路径 B 文件结构识别失败
    case tokenDecryptionFailed            // 路径 B token 加密无法解
    case allPathsFailed([Error])          // 全部 4 条路径都失败
}

// 实现按路径组合：
final class AccountsdImporter: SystemSessionImporter { /* 路径 A */ }
final class FileSystemImporter: SystemSessionImporter { /* 路径 B */ }
final class CompositeImporter: SystemSessionImporter {
    init(strategies: [SystemSessionImporter]) { ... }
    // 按顺序 try，第一个成功即返回
}
```

`AppStoreClient` 完全不感知账号来源——它只接受 `Account`。这点是关键：stealth 与 manual 共享所有下游协议代码。

### 8.6 与 v0.2 的工程差异（增量清单）

- **新增**：`Core/SystemSession/` 目录，含 `SystemSessionImporter.swift` + 各路径实现 + `BinaryCookiesParser.swift`。
- **新增**：`Core/SystemSession/AccountsdBridge.{m,h}`（Swift 不能直接 KVC 调私有 framework，用 ObjC 封一层）。
- **修改**：`Models/Account.swift` 加 `enum Source { case systemBorrowed, manual }` 字段。
- **修改**：`AccountManager` 持有的账号列表区分 source；UI 列表加图标区分。
- **修改**：`entitlements.plist` 在 M0.5 通过后追加 `com.apple.accounts.appleaccount.fullaccess` 等私有 ent。
- **删除**：无（manual 路径完整保留）。

---

> **下一步**：按本目录结构在 2 号文档里把空骨架（`Makefile`、`Info.plist`、`entitlements.plist`、各 `.swift` 占位）写出来，**M0.5 PoC 单独立 3 号文档**，把四条路径在四个 iOS 版本上的实测结果做成兼容矩阵；之后再按 M1 → M6 顺序推进协议实现。
