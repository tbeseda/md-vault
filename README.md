# md-vault

A fast, native macOS app for viewing and editing a folder ("vault") of markdown files. Pure SwiftUI with one dependency (Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown)), built to coexist with coding agents that read, edit, and create the same files on disk.

The editor is a hybrid live-styled source view: what's on disk is exactly what you see, with markdown syntax visible but styled in place.

Requires macOS 26.

## Install

### Homebrew

```sh
brew tap tbeseda/tap
brew install --cask md-vault
```

### Manual

Download `md-vault.zip` from the [latest release](../../releases/latest), unzip, and move to `/Applications`.

The app is not signed. To open it for the first time, either:

- Run `xattr -cr /Applications/md-vault.app` in Terminal, then open normally
- Or attempt to open, then go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway**

## Build from source

Requires Xcode 26.

```sh
xcodebuild -project md-vault.xcodeproj -scheme md-vault -configuration Release build
```

## Tests

Unit tests use [Swift Testing](https://developer.apple.com/documentation/testing) and live in `MDVaultTests/`:

```sh
xcodebuild -project md-vault.xcodeproj -scheme md-vault test
```

## Releasing

Pushing a `v*` tag triggers [release.yml](.github/workflows/release.yml): it runs the tests, builds Release, zips the app, publishes a GitHub release with the zip and its SHA256, and bumps the version and sha in the [tbeseda/homebrew-tap](https://github.com/tbeseda/homebrew-tap) cask. Bump `MARKETING_VERSION` in the pbxproj to match the tag before tagging.
