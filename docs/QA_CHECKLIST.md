# Vector Vortex — maintainer reference

Repository: https://github.com/peter-dietrich/vector-vortex  
macOS bundle: `io.vectorvortex.game`  
Runtime: macOS 14+  
SDKs: SwiftUI, SpriteKit, AVFoundation, AppKit

## Automated CI scope

The current GitHub Actions `macOS build` workflow compiled the audited `main` commit successfully. This is **compile validation only**; it does not prove correctness of interactive gameplay, signing, notarization, audio rights, or macOS Gatekeeper acceptance.

```sh
xcodebuild -project VectorVortex.xcodeproj -scheme VectorVortex -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Manual smoke tests

Verify tube changes, lane movement and firing, pulse availability, all enemy variants, ammo recharge and hit registration, pause/resume, custom presets, twelve save slots and live sound levels.

## Pre-release checklist

- [ ] Build on the intended Xcode/macOS combinations, test start, game over, pause, input focus and window resizing.
- [ ] Test Classic/Modern display transitions, score update, gameplay rules, effects, sound toggle and accessibility of text.
- [ ] Verify all save/preset options, invalid/missing saved data and restart behavior.
- [ ] Check performance, app logs, missing bundled resources, crashes, and restart after uninstall/reinstall.
- [ ] Confirm MIT copyright permission, tracked audio/art provenance, external dependencies and trademark/visual-expression review.
- [ ] For public distribution, test signed/notarized archive, checksum, Gatekeeper open on clean Mac, and Fun City's in-app installer.

Record commit SHA, workflow URL, macOS/Xcode versions, tested behavior, screenshots/observations and outstanding defects. Do not mark legal clearance complete based on CI alone.
