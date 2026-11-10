# Vector Vortex

An original, Tempest-inspired neon tube shooter for macOS, built in SwiftUI and SpriteKit. A standalone cabinet for [Fun City](https://github.com/peter-dietrich/fun-city). No external frameworks, artwork, game assets, telemetry uploads, or server dependency.

## Play

Open **VectorVortex.xcodeproj** in Xcode 16+ (macOS 14+) and run the **VectorVortex** scheme on **My Mac**. The game runs in its own resizable window.

| Control | Action |
|---|---|
| Return | Start / restart / resume |
| Left / Right or A / D | Move the ship around the tube rim |
| Space | Fire inward toward enemies |
| Shift | Use a one-per-wave pulse that destroys nearby climbers and rim runners |
| P | Pause / resume |
| 1 / 2 | Classic / Modern visualization |
| Mouse | Click game to restore keyboard focus |

## Gameplay

Enemies emerge from the center and climb along polygonal lanes toward the rim. Shoot them before they escape. Some switch lanes (flippers), some require two hits (armored), and enemies reaching the rim can become runners. Colliding with a runner costs a life. Clear all enemies to advance to the next wave with another tube shape and a bigger threat.

- **Classic**: bright wireframe geometry on a dark arcade screen.
- **Modern**: denser luminous depth panels, soft glow, saturated colors, and glass-like telemetry.
- **Difficulties**: Cadet, Veteran, Ace.
- **Custom Game**: adjustable lane count, ship motion, firing interval, lives, spawns, growth, enemy speed and variants; named local presets.
- **Save & Load**: up to 12 resumable sessions, stored locally with UserDefaults; also a persistent high score.
- **Ammo**: 500 rounds, automatically restores at 100 rounds/s after 5 seconds of not firing.
- **Arcade audio**: generated sine/retro effect sounds in memory via AVFoundation; no bundled audio or music licensing required.

No third-party Tempest logos, code, or original game assets are used.

## Build

```sh
xcodebuild -project VectorVortex.xcodeproj -scheme VectorVortex -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow builds on macOS whenever code is pushed. The macOS build and actual gameplay have not been verified locally from this environment until CI completes.

## Fun City

The launcher uses bundle ID `io.vectorvortex.game`. Build Vector Vortex, open Fun City, select the Vector Vortex cabinet, and use **LOCATE GAME** to select the built .app if macOS does not discover the bundle automatically.

## Project layout

- `Sources/VortexModel.swift` — rules, enemy data, snapshots, preset and save storage.
- `Sources/VortexScene.swift` — SpriteKit simulation, rendering, keyboard actions and synthesized sound effects.
- `Sources/VectorVortexApp.swift` — native macOS window, controls, custom rule editor, local save picker.
