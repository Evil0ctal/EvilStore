# EvilStore

Offline App Store companion for [TrollStore](https://github.com/opa334/TrollStore).
Pulls historic versions of your already-purchased apps from Apple's storefront and
hands the resulting `.ipa` to TrollStore for permanent install.

> Status: pre-alpha. Not yet usable.

## What it does

- Borrows your active App Store session (no second login in this app).
- Lists every historic version of an app via `softwareVersionExternalIdentifier`.
- Downloads the chosen version, injects `iTunesMetadata.plist` and `sinf` tickets.
- Hands the `.ipa` to TrollStore via `apple-magnifier://install?url=...`.

Falls back to manual Apple ID login if the system session can't be borrowed.

## Requirements

- iPhone or iPad with TrollStore installed (iOS 14.0 - 16.6.1, 16.7 RC, or 17.0).
- macOS with Xcode 15+ and `ldid`/`coreutils`/`xcbeautify` for building.
- A **secondary** Apple ID. Do not use your main account.

## Build

CI is the authoritative builder; local builds are optional.

```sh
brew install xcodegen ldid coreutils jq xcbeautify
Scripts/build_tipa.sh                  # -> build/EvilStore.tipa
```

The `.xcodeproj` is not committed; it is regenerated from
[`project.yml`](./project.yml) by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
on every build. See [docs/M0_GETTING_STARTED.md](./docs/M0_GETTING_STARTED.md).

## Install

AirDrop `build/EvilStore.tipa` to the device, then open it in TrollStore.

## Docs

- [1. Architecture](./docs/1_project_overview_and_architecture.md)
- [2. Build & directory layout](./docs/2_directory_skeleton_and_build.md)
- [3. UI design](./docs/3_ui_design_and_wireframes.md)
- [M0 getting started](./docs/M0_GETTING_STARTED.md)

## Acknowledgements

- [`ipatool`](https://github.com/majd/ipatool) - storefront protocol reference
- [`TrollStore`](https://github.com/opa334/TrollStore) - install pipeline
- [`Asspp`](https://github.com/Lakr233/Asspp) and
  [`ApplePackage`](https://github.com/Lakr233/ApplePackage) - Swift port reference

Not affiliated with Apple Inc.

## License

GPL-2.0-only. See [LICENSE](./LICENSE).
