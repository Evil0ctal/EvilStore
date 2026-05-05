# M0 — Getting Started

> The Xcode project is generated from [`project.yml`](../project.yml) by
> [XcodeGen](https://github.com/yonaskolb/XcodeGen). Nothing about the project
> structure lives in a hand-edited `.xcodeproj`; it is rebuilt every time you
> run `Scripts/build_tipa.sh` (or open Xcode after `xcodegen generate`).
>
> CI is the authoritative builder. Local builds are optional.

---

## 0. Local prerequisites (only if you want to build on your Mac)

```sh
brew install xcodegen ldid coreutils jq xcbeautify
xcode-select -p          # /Applications/Xcode.app/.../Developer
xcodebuild -version      # >= 15.0
```

CI does the same install on macos-14 runners.

---

## 1. Build a TIPA

```sh
Scripts/build_tipa.sh
# -> build/EvilStore.tipa
```

The script:
1. runs `xcodegen generate` if `EvilStore.xcodeproj` is missing or stale
2. `xcodebuild archive` with signing disabled
3. ldid fakesigns the binary with `EvilStore/Resources/entitlements.plist`
4. zips into `build/EvilStore.tipa`

---

## 2. Open in Xcode (optional)

```sh
xcodegen generate
open EvilStore.xcodeproj
```

Edit `project.yml` and re-run `xcodegen generate` whenever you add a new top-level
source folder. Files inside an already-listed folder are picked up automatically.

---

## 3. Install on device

AirDrop `build/EvilStore.tipa` to the iPhone, open in TrollStore, install.
Or via the helper:

```sh
Scripts/install_local.sh                              # opens Finder for AirDrop
Scripts/install_local.sh ssh root@iphone.local /var/mobile/Downloads/
```

Verify entitlements actually landed:

```sh
ldid -e build/stage/Payload/EvilStore.app/EvilStore | head
# expect: <key>com.apple.private.security.no-sandbox</key>
```

Acceptance: home screen icon appears, launching shows a 4-tab "Hello, EvilStore".

---

## 4. CI build

Every push to `main` and every PR runs `.github/workflows/{build,lint}.yml`:

- `build`: xcodegen + ldid + `Scripts/build_tipa.sh` -> uploads `EvilStore.tipa` as artifact.
- `lint`: swiftformat + swiftlint + SPDX header check + `xcodebuild build` (no tests; see [2-doc §8.8](./2_directory_skeleton_and_build.md#88-真机测试为什么不上-ci)).
- Tag push `v*` triggers a GitHub release with the TIPA attached.

To grab the latest CI build without compiling locally: open the latest green run
under Actions, download the `EvilStore-tipa` artifact, AirDrop to device.

---

## 5. Troubleshooting

| symptom | fix |
|---|---|
| `xcodegen missing` | `brew install xcodegen` |
| `ldid missing` | `brew install ldid` |
| `xcodebuild` says "no signing certificate" | xcconfig wiring is wrong; check `Configuration/Base.xcconfig` is referenced in `project.yml` |
| TrollStore error 180 (encrypted main binary) | bitcode slipped through; `ENABLE_BITCODE=NO` is set in Base.xcconfig — re-run build_tipa.sh |
| TrollStore error 179 (system app conflict) | `PRODUCT_BUNDLE_IDENTIFIER` in xcconfig clashes with a system app id; do not change away from `com.evil0ctal.evilstore` |
| Launches but immediately crashes | `ldid -e` shows no entitlements -> ldid path issue; `which ldid` should be the brew one |
| NSLog smoke message missing in Console.app | filter by `[EvilStore]`; if absent, ldid did not stamp the binary or the install path was rejected by amfi |

---

## 6. Commit

Commit style is enforced; see [2-doc §7.7](./2_directory_skeleton_and_build.md#77-消息风格--注释commitrelease-notes).

```sh
git add .
git commit -m "build: skeleton boots under trollstore"
```
