# md-vault

A fast, native macOS app for viewing and editing a folder ("vault") of markdown files. Pure SwiftUI with one dependency (Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown)), built to coexist with coding agents that read, edit, and create the same files on disk.

The editor is a hybrid live-styled source view: what's on disk is exactly what you see, with markdown syntax visible but styled in place.

Requires macOS 26 and Xcode 26. Build from source:

```sh
xcodebuild -project md-vault.xcodeproj -scheme md-vault -configuration Release build
```
