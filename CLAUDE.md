# CLAUDE.md
- 常に日本語で回答する
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OmatsuriTopia is an iOS game built with SpriteKit and GameplayKit. The project uses the standard Xcode project structure with a single target application.

## Build Commands

This is an Xcode project that must be built using `xcodebuild`:

```bash
# Build the project
xcodebuild -project OmatsuriTopia.xcodeproj -scheme OmatsuriTopia -configuration Debug build

# Build for release
xcodebuild -project OmatsuriTopia.xcodeproj -scheme OmatsuriTopia -configuration Release build

# Clean build folder
xcodebuild -project OmatsuriTopia.xcodeproj -scheme OmatsuriTopia clean
```

To run the app, open `OmatsuriTopia.xcodeproj` in Xcode and use Cmd+R, or use the iOS Simulator via command line.

## Architecture

### Core Components

**AppDelegate** (`OmatsuriTopia/AppDelegate.swift`)
- Entry point of the application
- Handles application lifecycle events (background, foreground, active/inactive states)
- Standard UIKit app delegate pattern

**GameViewController** (`OmatsuriTopia/GameViewController.swift`)
- UIViewController that hosts the SpriteKit scene
- Loads `GameScene.sks` as a GKScene (GameplayKit scene)
- Transfers entities and graphs from GKScene to SKScene
- Configures debug views (FPS, node count) via `view.showsFPS` and `view.showsNodeCount`
- Sets scene scale mode to `.aspectFill`
- Manages interface orientations (all but upside down on iPhone, all on iPad)

**GameScene** (`OmatsuriTopia/GameScene.swift`)
- Main SpriteKit scene that runs the game loop
- Manages GameplayKit entities and graphs loaded from the `.sks` file
- Implements touch handling with visual feedback (colored spinny nodes)
- Contains a label node ("helloLabel") referenced from `GameScene.sks`
- Update loop processes delta time and updates all entities

### GameplayKit Integration

The project uses GameplayKit's entity-component system:
- **Entities** (`entities` array): Game objects managed by GameplayKit
- **Graphs** (`graphs` dictionary): Pathfinding and AI graphs
- Both are loaded from `GameScene.sks` and transferred to the scene in `GameViewController`
- Entities are updated each frame in `GameScene.update(_:)` with delta time

### Scene Loading Flow

1. `GameViewController.viewDidLoad()` loads `GameScene.sks` as a `GKScene`
2. The `GKScene.rootNode` is cast to `GameScene`
3. Entities and graphs are copied from `GKScene` to `GameScene`
4. Scene is presented with debug info enabled

### Touch Interaction

Touch handling creates colored shape nodes at touch points:
- Touch down: green
- Touch moved: blue
- Touch up/cancelled: red
- Each creates a spinning, fading node using `SKAction` sequences

## Project Configuration

- **Bundle ID**: `jp.hibiki.OmatsuriTopia`
- **Development Team**: `AK92W9FN2D`
- **Deployment Target**: iOS 26.2
- **Swift Version**: 5.0
- **Supported Devices**: iPhone and iPad (universal)
- **Swift Concurrency**: Uses MainActor isolation and approachable concurrency features
- **Status Bar**: Hidden during gameplay

## File Organization

```
OmatsuriTopia/
├── OmatsuriTopia.xcodeproj/     # Xcode project file
└── OmatsuriTopia/                # Source directory
    ├── AppDelegate.swift         # App lifecycle
    ├── GameViewController.swift  # Scene hosting
    ├── GameScene.swift          # Main game logic
    ├── GameScene.sks            # Scene editor file (entities, graphs, nodes)
    ├── Actions.sks              # Reusable SpriteKit actions
    ├── Base.lproj/
    │   ├── Main.storyboard      # UI storyboard
    │   └── LaunchScreen.storyboard
    └── Assets.xcassets/         # Image and color assets
```

## Development Notes

- The project uses FileSystemSynchronizedRootGroup for automatic file management
- Debug builds show FPS and node count by default
- Scene uses aspect fill scaling, ensuring the scene fills the screen
- All UI interactions hide the status bar for immersive gameplay
