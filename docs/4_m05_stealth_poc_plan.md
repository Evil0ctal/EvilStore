# M0.5 — Stealth PoC 实测计划（4 号文档）

> 版本：v0.1
> 日期：2026-05-05
> 前置：1 号 v0.3 §8 / 2 号 v0.3 §10 M0.5 / 3 号 v0.1 §8.4
>
> **本文档定位**：把 1 号文档 §8 提出的"借用系统 App Store 会话"四条路径（A `accountsd` / B 文件系统 / C Keychain 越组 / D XPC `storeaccountd`）从"理论可行"推到"实测有结果"。M0.5 milestone 的全部产出物都列在此处，验收门槛在 §6。
>
> **严格阶段约束**：M0.5 **只做探测和 diagnostics**，不写任何会消耗探测结果的业务代码（`AppStoreClient` 在 M1 才动）。

---

## 目录

- [0. 目标与门槛](#0-目标与门槛)
- [1. 路径 A：accountsd 私有 framework](#1-路径-a--accountsd-私有-framework)
- [2. 路径 B：filesystem dump](#2-路径-b--filesystem-dump)
- [3. 路径 C：keychain 越组](#3-路径-c--keychain-越组)
- [4. 路径 D：XPC storeaccountd](#4-路径-d--xpc-storeaccountd)
- [5. 兼容矩阵收集与 Diagnostics 工具](#5-兼容矩阵收集与-diagnostics-工具)
- [6. 验收门槛](#6-验收门槛)
- [7. 风险与回退](#7-风险与回退)
- [8. 任务拆解（开发顺序）](#8-任务拆解开发顺序)

---

## 0. 目标与门槛

**目标**：在 iOS 14 / 15 / 16 / 17 至少**任一档**真机上，从系统已登录的 App Store 中读取出一份**可立即用于 storefront API 调用**的会话快照：

```swift
struct StealthSnapshot {
    var dsid: String                        // required
    var altDSID: String?                    // best effort
    var passwordToken: String?              // best effort; without it lookup/list still work via cookies
    var storefront: String                  // required ("143441" etc)
    var guid: String                        // required (12 hex)
    var cookies: [HTTPCookie]                // required (at least itunesstored set)
    var sourcePath: PathName                 // which strategy succeeded
    var capturedAt: Date
}
```

**M0.5 通过门槛**（任一组合即可，但必须有书面证据）：

1. **至少一条路径**（A / B / C / D 任一）在**至少一档 iOS**（14 / 15 / 16 / 17 任一）上拿到 `dsid + storefront + guid + cookies`。
2. 用这个 snapshot 手工构造一个 `iTunes Lookup` 请求（公开端点 `/lookup?bundleId=...&country=US`）应当返回正常 200。这条**只是连通性烟囱**，不验证 storefront 私有协议（私有协议留 M1）。
3. 输出物（§5.2）markdown 报告 + 对应代码 + entitlements 增量已合入。

**未通过的处置**：触发 1-doc §8 写明的 "fallback" 路径——M1 直接做 manual 登录，stealth 模式延后或弃用。我们**不会**在 M0.5 失败时硬撑。

---

## 1. 路径 A — accountsd 私有 framework

### 1.1 原理摘要

`Accounts.framework`（公开 API）+ 几个私有 type identifier（`com.apple.account.AppleAccount` / `com.apple.account.iTunesStore`）。`ACAccountStore` 列出账户、读 `properties` 字典里的 `DSID` / `AltDSID` / `storefront` / `oauthToken`。

### 1.2 所需 entitlements（PoC 阶段先全开，跑通后剪到最小）

```xml
<key>com.apple.accounts.appleaccount.fullaccess</key>
<true/>
<key>com.apple.private.accounts.bundleidspoofing</key>
<true/>
```

合入位置：`EvilStore/Resources/entitlements.plist`。**不进 main 分支的 entitlements**——先在 PoC 分支 `feat/m0.5-stealth-poc` 试，跑通 + diagnostics 报告归档后再 squash merge。

### 1.3 代码骨架

```objc
// EvilStore/Core/SystemSession/AccountsdBridge.h
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@interface ESAccountsdBridge : NSObject
+ (BOOL)isAvailable;
/// keys: email, dsid, altDSID, oauthToken, storefront. Any may be missing.
+ (nullable NSDictionary *)copyAppleIDAccountInfoWithError:(NSError *_Nullable *_Nullable)errorOut;
+ (nullable NSDictionary *)copyiTunesStoreAccountInfoWithError:(NSError *_Nullable *_Nullable)errorOut;
@end

NS_ASSUME_NONNULL_END
```

```objc
// EvilStore/Core/SystemSession/AccountsdBridge.m
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

#import "AccountsdBridge.h"
#import <Accounts/Accounts.h>

static NSDictionary *copyForType(NSString *typeID, NSError **errorOut) {
    ACAccountStore *store = [[ACAccountStore alloc] init];
    ACAccountType *type = [store accountTypeWithAccountTypeIdentifier:typeID];
    if (!type) {
        if (errorOut) *errorOut = [NSError errorWithDomain:@"ESAccountsd" code:404
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"unknown type %@", typeID]}];
        return nil;
    }
    NSArray<ACAccount *> *accounts = [store accountsWithAccountType:type];
    ACAccount *acc = accounts.firstObject;
    if (!acc) return nil;

    NSMutableDictionary *out = [NSMutableDictionary new];
    out[@"email"] = acc.username ?: @"";
    out[@"identifier"] = acc.identifier ?: @"";
    // properties is private; reach via KVC
    @try {
        NSDictionary *props = [acc valueForKey:@"properties"];
        if ([props isKindOfClass:NSDictionary.class]) {
            if (props[@"DSID"])       out[@"dsid"]       = [props[@"DSID"]       description];
            if (props[@"AltDSID"])    out[@"altDSID"]    = [props[@"AltDSID"]    description];
            if (props[@"storefront"]) out[@"storefront"] = [props[@"storefront"] description];
        }
    } @catch (__unused NSException *exc) {}
    @try {
        ACAccountCredential *cred = acc.credential;
        if (cred.oauthToken) out[@"oauthToken"] = cred.oauthToken;
    } @catch (__unused NSException *exc) {}
    return out;
}

@implementation ESAccountsdBridge
+ (BOOL)isAvailable { return NSClassFromString(@"ACAccountStore") != nil; }
+ (NSDictionary *)copyAppleIDAccountInfoWithError:(NSError **)errorOut {
    return copyForType(@"com.apple.account.AppleAccount", errorOut);
}
+ (NSDictionary *)copyiTunesStoreAccountInfoWithError:(NSError **)errorOut {
    return copyForType(@"com.apple.account.iTunesStore", errorOut);
}
@end
```

### 1.4 验证步骤

1. 切到 `feat/m0.5-stealth-poc` 分支。
2. 把上面两个 ObjC 文件加入 `EvilStore/Core/SystemSession/`，更新 `project.yml`（增加 `EvilStore-Bridging-Header.h` + 把 `Core/SystemSession` 加进 sources，已在 §8 任务中列）。
3. 在 `RootView` 临时塞一个 debug 按钮 "probe accountsd"，触发后把 dict 通过 `Logger.info(sanitize:)` 打到系统日志，并用 `UIPasteboard` 把 markdown 报告复制出来（敏感字段 tail-4 mask）。
4. 装到目标设备（iOS 14 / 15 / 16 / 17 任一）跑一次。
5. **Console.app** filter `[EvilStore]` 看输出；记录哪些 key 拿到了、哪些 nil。
6. 把脱敏报告粘进 `docs/m05_diagnostics/<ios-version>_path_a.md`。

### 1.5 失败模式（已知 / 预期）

| 现象 | 处理 |
|---|---|
| `ACAccountStore` 实例化即 crash / SIGABRT | entitlement 没生效（`ldid -e` 检查）→ 路径 A 在该 iOS 版本不可达，跳路径 B |
| accountsArray 空 | 系统未登录 App Store → diagnostic 引导用户先去系统设置登录，再重跑 |
| `properties` KVC 抛 `NSUndefinedKeyException` | 该 iOS 版本 ACAccount 内部字段重命名 → 改用其它 KVC key（`accountProperties` 之类）逐个尝试，失败计入兼容矩阵 |
| `oauthToken` nil 但 dsid/storefront 都有 | 正常；passwordToken 不是必需，cookies 能续会话 |
| `storefront` 格式像 `143441-19,29` | 取首段 `143441` 即可（参考 ApplePackage `Authenticate.swift::parseResponse`） |

---

## 2. 路径 B — filesystem dump

### 2.1 原理摘要

`com.apple.private.security.no-sandbox` + `files.absolute-path.read-write = ["/"]`（M0 已有）让我们能直接读：

```
/var/mobile/Library/com.apple.itunesstored/
    accountInfo                       # plist: dsid, email, storefront, guid
    accountTokens                     # plist: passwordToken (sometimes encrypted)

/var/mobile/Library/Cookies/
    com.apple.itunesstored.binarycookies
```

### 2.2 不需要新 entitlements

M0 最小集已够用；这是路径 B 相对路径 A 的主要优势。

### 2.3 代码骨架

```swift
// EvilStore/Core/SystemSession/FileSystemImporter.swift
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

final class FileSystemImporter: SystemSessionImporter {
    let name = "filesystem"
    private let storeRoot = URL(fileURLWithPath: "/var/mobile/Library/com.apple.itunesstored")
    private let cookiesPath = URL(fileURLWithPath:
        "/var/mobile/Library/Cookies/com.apple.itunesstored.binarycookies")

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: storeRoot.path)
    }

    func snapshot() async throws -> Account {
        let info = try readAccountInfo()           // accountInfo plist
        let cookies = try BinaryCookiesParser.parse(at: cookiesPath)
        let token = try? readAccountTokens()       // best effort
        return Account(
            source: .systemBorrowed,
            email: info.email,
            firstName: info.firstName,
            lastName: info.lastName,
            directoryServicesIdentifier: info.dsid,
            passwordToken: token,
            storefront: info.storefront,
            pod: nil,
            guid: info.guid,
            cookies: cookies.map(HTTPCookieBox.init),
            encryptedPassword: nil
        )
    }

    private func readAccountInfo() throws -> AccountInfoFile { unimplementedThrowing() }
    private func readAccountTokens() throws -> String { unimplementedThrowing() }
}

private struct AccountInfoFile {
    var email: String, firstName: String, lastName: String
    var dsid: String, storefront: String, guid: String
}
```

### 2.4 BinaryCookiesParser

Apple Binary Cookies v0x100 格式（公开规范）。M0.5 阶段一并实现。

```swift
// EvilStore/Core/SystemSession/BinaryCookiesParser.swift
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

enum BinaryCookiesParser {
    static func parse(at url: URL) throws -> [HTTPCookie] { unimplementedThrowing() }
}
```

参考实现：[liamnichols/BinaryCookies-Swift](https://github.com/liamnichols/BinaryCookies-Swift)（MIT，可港）或自己 100 行写完——格式简单，主要是 big-endian 整数 + 几个 fixed offset。

### 2.5 验证步骤

1. 进 PoC 分支，加 `FileSystemImporter` + `BinaryCookiesParser`。
2. Settings 加 debug 按钮 "probe filesystem"。
3. 真机跑，对每个 iOS 版本：
   - `ls -la /var/mobile/Library/com.apple.itunesstored/` 截图
   - `plutil -p .../accountInfo` 看字段名
   - 解析后报告写入 `docs/m05_diagnostics/<ios-version>_path_b.md`
4. 拿到的 cookies 数 + DSID + GUID 与路径 A（如果 A 也通了）对照——理论上 GUID / DSID 一致；如果不一致**优先信路径 B**（更接近系统真实持久化状态）。

### 2.6 失败模式

| 现象 | 处理 |
|---|---|
| `accountInfo` 找不到字段 / 字段名跨版本不同 | 记录该版本 key 名差异；用 `Codable` 时 `CodingKeys` 用 `try?` 多备选 key |
| `accountTokens` 加密读不出 | 不影响 lookup/list；记入"token unavailable on this iOS"列。download 路径在 M3 时按 cookies + DSID 是否够再决定 |
| `Cookies.binarycookies` 不存在 | 系统从未通过 App Store 发过请求；diagnostic 指引 "open App Store once" |
| `permission denied` 即便有 no-sandbox | 检查 ldid 真的把 ent 写进去了；`ldid -e` |

---

## 3. 路径 C — keychain 越组

### 3.1 原理摘要

App Store 把核心 token 存在 access group `com.apple.itunesstored`。第三方默认进不去；带上私有 entitlements 通配可越组。

### 3.2 所需 entitlements

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

iOS 16+ 收紧严重；iOS 14/15 大概率工作。

### 3.3 代码骨架

```swift
// EvilStore/Core/SystemSession/KeychainImporter.swift
// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation
import Security

final class KeychainImporter: SystemSessionImporter {
    let name = "keychain"
    func isAvailable() async -> Bool { true }

    func snapshot() async throws -> Account {
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccessGroup: "com.apple.itunesstored",
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnData: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let items = out as? [[CFString: Any]] else {
            throw SystemSessionError.entitlementDenied("keychain access group not granted (status=\(status))")
        }
        // walk items, look for kSecAttrAccount == "DSID" / "passwordToken" etc
        unimplementedThrowing()
    }
}
```

### 3.4 验证步骤

精简版：先**只**枚举 access group 内有哪些 keychain item（不解析 value），把 `kSecAttrService` / `kSecAttrAccount` 全列出来写进 diagnostic。然后再针对 DSID/passwordToken 这些 key 单独取 data。

iOS 16+ 上即便 entitlements 全有也可能 `errSecMissingEntitlement` (`-34018`) —— 这是 PoC 必须实测的。

### 3.5 决策点

如果路径 C 在 iOS 16+ 全军覆没，**不强行** —— 路径 B 已能覆盖大部分场景。把 C 留作"iOS 14/15 老设备额外加分项"。

---

## 4. 路径 D — XPC storeaccountd

### 4.1 原理摘要

`com.apple.storeaccountd` mach service 暴露的 XPC 接口。系统设置就是这么取账号的。

### 4.2 维护成本

跨 iOS 版本接口 selector + parameter shape 变化大；每次 iOS major 升级要重新逆向。**M0.5 不实现**，仅在 diagnostic 工具中预留入口位置（`status: skipped, reason: not implemented in M0.5`），等路径 A/B/C 全部失败的极端情形再回头。

---

## 5. 兼容矩阵收集与 Diagnostics 工具

### 5.1 Settings 中的 debug 入口

3 号文档 §8.4 已规划过 UI；本节落实 M0.5 实现：

```swift
// EvilStore/UI/Settings/StealthDiagnosticsView.swift
#if DEBUG
struct StealthDiagnosticsView: View { ... }
#endif
```

仅 `#if DEBUG` 编译进；release TIPA 看不到。

按钮：
- `Run all paths` —— 顺序跑 A → B → C → D，每条独立 `Result`，UI 实时显示 `[✓] / [✗] / [·]`。
- `Export markdown report` —— 生成 §5.2 格式的报告，share sheet 出去。

### 5.2 Markdown 报告模板

```markdown
# stealth probe report

device     : iPhone 12 Pro
ios        : 16.6.1 (20G81)
trollstore : 2.0.12
evilstore  : 0.2.0 (build 5) commit abc1234
captured   : 2026-05-09T22:14:33Z

## path A — accountsd
status   : ok
elapsed  : 38ms
fields   :
  email      : evil0ctal_alt@icloud.com
  dsid       : 2113xxxxxxxx
  altDSID    : 0001-XXXX-XXXX-XXXX-XXXX
  storefront : 143441
  oauthToken : 45 chars (tail4: ...a8c2)

## path B — filesystem
status   : ok
elapsed  : 12ms
files    :
  accountInfo   : 4138 bytes (last_modified 2026-05-08T11:02:00Z)
  accountTokens : 824 bytes
  cookies       : 4 cookies from itunesstored
fields   :
  dsid       : 2113xxxxxxxx
  storefront : 143441
  guid       : F3A1•••••EC72
  passwordToken: present (62 chars, tail4: ...e3f9)

## path C — keychain
status   : denied
reason   : SecItemCopyMatching returned -34018 (errSecMissingEntitlement)

## path D — xpc storeaccountd
status   : skipped
reason   : not implemented in M0.5

## smoke test
itunes lookup (bundleId=org.telegram.Telegraph, country=US):
  http 200 in 240ms
  trackId 686449807 ✓
```

### 5.3 报告归档

每条 PoC 跑完一档 iOS 后，**脱敏** 后落盘到：

```
docs/m05_diagnostics/
    14_7_4_iphone_xs_path_a.md
    14_7_4_iphone_xs_path_b.md
    15_8_3_iphone_11_path_a.md
    16_6_1_iphone_12pro_path_a.md
    ...
    matrix.md                      # 汇总
```

`matrix.md` 是最终 M0.5 的 deliverable —— 一张表说尽 4 路径 × 4 iOS 大版本的 status。模板：

```markdown
| iOS         | path A | path B | path C | path D |
|-------------|--------|--------|--------|--------|
| 14.7.4      | ok     | ok     | ok     | skip   |
| 15.8.3      | ok     | ok     | denied | skip   |
| 16.6.1      | partial| ok     | denied | skip   |
| 17.0        | ?      | ?      | ?      | skip   |
```

`partial` 含义：路径 A 拿到 dsid/storefront 但 oauthToken 缺；fallback 到 B 补 token。

---

## 6. 验收门槛

M0.5 关闭条件（**任一**满足即可，但必须有书面证据）：

1. ✅ **`docs/m05_diagnostics/matrix.md`** 存在，至少一行 iOS × 一条 path 是 `ok`
2. ✅ 同档 iOS 的 smoke test（iTunes Lookup 公开 endpoint）走通
3. ✅ `Core/SystemSession/{SystemSessionImporter, CompositeImporter}.swift` + 至少一条 `*Importer.swift` 实装
4. ✅ `Resources/entitlements.plist` 已合入 §1.2 / §3.2 的私有 ent（按实测可达性最小化合入）
5. ✅ `StealthDiagnosticsView.swift`（`#if DEBUG`）能在装机后跑出 §5.2 模板的报告
6. ✅ commit history 至少含：`stealth: <area>: <imperative>` × N（按 §7.7 规则）
7. ✅ Bump 版本至 `0.2.0`，`Scripts/bump_version.sh minor` 然后 tag `v0.2.0`，CI 出 release

**未通过的处置**：见 §0 末尾。

---

## 7. 风险与回退

### 7.1 风险

| 风险 | 缓解 |
|---|---|
| iOS 17 全部路径都失败 | M1 直接走 manual 登录，stealth 模式 release notes 注明"iOS 14-16 only" |
| 私有 entitlement 在某档 iOS 上让 amfi 直接拒进程（启动闪退）| `ldid -e` 反查 entitlements；逐 key 减半试错；最坏情况发布带"M0 ent only"的 emergency build |
| storefront 风控因 PoC 频繁请求触发 | PoC 阶段所有真协议请求**手动控量**，每个 iOS 版本最多 5 次 lookup 不打 list/download |
| 测试设备数量不足覆盖矩阵 | 在 issue 描述中明示哪些 iOS 没测；社区 PR 补 |

### 7.2 回退操作

如果 M0.5 整体失败：

1. revert `feat/m0.5-stealth-poc` 分支，**不**合入 main
2. 把 `1-doc §8` 的 stealth 章节标记为 "tentative; see m05 diagnostics"
3. 把 M1 任务表（2-doc §10 M1）改为"manual 登录优先 + stealth 占位"
4. 文档加一句"contributions welcome"——也许后续 iOS 版本更新或社区 PR 能恢复 stealth

---

## 8. 任务拆解（开发顺序）

> 严格顺序；每步独立 commit；commit message 走 §7.7。

### 8.1 准备分支

```sh
git checkout -b feat/m0.5-stealth-poc
```

### 8.2 task 1 — 工程结构 + 基础 protocol

新增 / 修改：

```
EvilStore/Core/SystemSession/SystemSessionImporter.swift   (protocol + error enum)
EvilStore/Core/SystemSession/CompositeImporter.swift       (chain strategies)
EvilStore/Util/Unimplemented.swift                          (helper)
project.yml                                                 (add Core/ to sources)
EvilStore-Bridging-Header.h                                 (empty for now)
```

提交：`stealth: scaffold importer protocol`

### 8.3 task 2 — Path B（先做风险最低的）

```
EvilStore/Core/SystemSession/BinaryCookiesParser.swift
EvilStore/Core/SystemSession/FileSystemImporter.swift
EvilStoreTests/SystemSessionTests/BinaryCookiesParserTests.swift
EvilStoreTests/Fixtures/sample.binarycookies
```

提交：`stealth: parse itunesstored cookies + accountInfo`

### 8.4 task 3 — Path A

```
EvilStore/Core/SystemSession/AccountsdBridge.{h,m}
EvilStore/Core/SystemSession/AccountsdImporter.swift
project.yml                                                 (add bridging header)
EvilStore/Resources/entitlements.plist                      (add §1.2 ents)
```

提交：`stealth: read appleid via accountsd kvc`

### 8.5 task 4 — Path C

```
EvilStore/Core/SystemSession/KeychainImporter.swift
EvilStore/Resources/entitlements.plist                      (add §3.2 ents)
```

提交：`stealth: try itunesstored keychain access group`

### 8.6 task 5 — Diagnostics UI

```
EvilStore/UI/Settings/StealthDiagnosticsView.swift          (#if DEBUG)
EvilStore/UI/Settings/SettingsView.swift                    (placeholder + debug entry)
EvilStore/UI/Root/RootView.swift                            (link Settings tab)
EvilStore/Util/Logger.swift                                 (sanitize redaction helpers)
```

提交：`stealth: diagnostics view + markdown export`

### 8.7 task 6 — 真机跑测 + diagnostics 归档

为每档 iOS 重复：
1. `Scripts/build_tipa.sh && Scripts/install_local.sh`
2. 装上后 Settings → Stealth diagnostics → Run all paths → Export markdown
3. AirDrop 报告到 macOS，**手工脱敏后**落 `docs/m05_diagnostics/<ver>_<device>.md`
4. 更新 `docs/m05_diagnostics/matrix.md` 对应行
5. 提交：`docs: m05 matrix +<ios-version> path A/B/C results`

### 8.8 task 7 — 收尾

- 把 ent 文件按"实测必要的最小集"剪一遍（如果路径 C 全部失败，就把 keychain 三件 ent 删掉）
- `Scripts/bump_version.sh minor`（→ 0.2.0）
- 1-doc §7.11 / 2-doc §13 / 3-doc 各自补一笔"M0.5 实测结果"
- PR 到 main，squash merge
- `git tag v0.2.0 && git push --tags` → CI 自动出 release

提交：`stealth: trim ents to verified minimum + bump 0.2.0`

---

> **审查重点**：
> 1. §0 验收门槛"任一档 iOS × 任一路径"是否过松？要不要至少 2 档？
> 2. §1.5 路径 A `properties` KVC 备选 key 列表怎么写？现在留空，跑一次后补
> 3. §2.4 BinaryCookiesParser 自写还是港 liamnichols 那个 100 行库？
> 4. §3.5 路径 C 如果 iOS 14/15 上也失败，整条 C 路径直接删？
> 5. §5.3 `docs/m05_diagnostics/` 目录是否进 git？我倾向**进**（脱敏后），让后续贡献者能看历史
> 6. §6 第 7 条 release on tag 是否过早？v0.2.0 时还没业务功能，发出去用户拿到的是空 stealth diagnostics
>
> 审完即可开 PoC 分支动手。
