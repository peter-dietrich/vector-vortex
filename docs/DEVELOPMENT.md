# Vector Vortex — maintainer reference

Repository: https://github.com/peter-dietrich/vector-vortex  
macOS bundle: `io.vectorvortex.game`  
Runtime: macOS 14+  
SDKs: SwiftUI, SpriteKit, AVFoundation, AppKit

## Architecture

Original neon tube shooter with Classic/Modern modes, pulse, climbers and rim runners. The standalone macOS application is built from `VectorVortex.xcodeproj` and sources under `Sources/`. The canonical app display name and bundle identifier are configured in the Xcode project. Preserve these across upgrades and releases.

This project is one of the five standalone game repositories linked by [Fun City](https://github.com/peter-dietrich/fun-city). The launcher does not contain or compile game source; its cabinet looks up the installed app by bundle ID or permits manual selection, and its download installer expects a signed release package from this game's canonical repository.

## Local development

1. Clone or update this repository: `git pull --ff-only origin main`.
2. Open `VectorVortex.xcodeproj` in Xcode 16+; select scheme `VectorVortex` and destination **My Mac**.
3. Run **⌘B** to build, **⌘R** to test play; clean (**⇧⌘K**) if Xcode's build products are stale.
4. Keep README, QA checks and release notes aligned when changing rules, controls, audio, save data or bundle ID.
5. Prefer feature branches and reviewed PRs for substantive changes; merge only known-good code into `main`.

## Persistence and integration

Game scores, preferences, custom rules and saved games/checkpoints (when supported) use local macOS persistence such as UserDefaults. They are **not** stored in GitHub, synced automatically or shipped within Fun City's launcher. Check the game's README for exact save/resume semantics, especially whether a resume restores a whole world state or starts a wave anew.

## Compatibility boundaries

Record the macOS minimum version, data migration behavior, bundle ID, Xcode scheme, app archive name and Fun City catalog mapping as compatibility requirements. Changing identifiers may break existing installs and saved games.
