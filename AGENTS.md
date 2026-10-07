# Repository Guidelines

## Project Structure & Module Organization

OmatsuriTopia is an iPhone/iPad shooting-gallery game using Swift, UIKit, SpriteKit, and GameplayKit.

- `OmatsuriTopia/`: application source. `GameScene.swift` owns gameplay, input, spawning, and game UI; `TargetEntity.swift` defines target types and attributes; `GameComponents.swift` contains reusable GameplayKit components.
- `GameViewController.swift` creates the scene programmatically; `AppDelegate.swift` and `SceneDelegate.swift` handle application lifecycle.
- `OmatsuriTopia/Assets.xcassets/`: target images, backgrounds, colors, and icons. `Base.lproj/` contains storyboards; `.sks` files contain SpriteKit resources.
- `OmatsuriTopia.xcodeproj/`: the single application target and build settings. No test directory or test target currently exists.

## Build, Test, and Development Commands

Use Xcode 26.2 or newer with an iOS 26 SDK; the deployment target is iOS 26.0 and Swift language mode is 5.0. Run commands from the repository root.

```bash
# Build for Simulator without device signing
xcodebuild -project OmatsuriTopia.xcodeproj -scheme OmatsuriTopia \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build

# Remove build products
xcodebuild -project OmatsuriTopia.xcodeproj -scheme OmatsuriTopia \
  -derivedDataPath build/DerivedData clean
```

Use `-configuration Release` for an optimized build. To run locally, open the project in Xcode, select the `OmatsuriTopia` scheme and an iPhone/iPad simulator, then press **Cmd+R**.

## Coding Style & Naming Conventions

Use four-space indentation, `UpperCamelCase` type names, and `lowerCamelCase` methods, properties, and enum cases. Match surrounding Swift style, use `private` for implementation details, and organize longer files with `// MARK: -` sections. No formatter or linter is configured.

Keep reusable behavior in GameplayKit components and scene orchestration in `GameScene`. When adding targets, update `TargetType`, attributes, spawn selection, and matching asset names such as `Target011` together.

## Testing Guidelines

No automated testing framework or coverage threshold is configured. Validate changes with a Simulator build and manual gameplay checks: aiming, firing, reload states, scoring, ammunition exhaustion, and replay. Check landscape layout on both iPhone and iPad. If introducing XCTest, add a test target, use `*Tests.swift` files and descriptive `test...` methods, and document its run command.

## Commit & Pull Request Guidelines

Recent commits use short Japanese summaries describing one change, such as `リロードボタンのデザインを刷新`. Follow that style and keep commits focused. PRs should explain behavior changes, link relevant issues, list build/manual checks, and include screenshots for UI changes. No PR template is present.

Keep generated builds and Xcode user settings untracked. Avoid unrelated signing or bundle-identifier changes; preserve landscape-only support and iPad full-screen behavior.
