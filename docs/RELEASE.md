# Vector Vortex — maintainer reference

Repository: https://github.com/peter-dietrich/vector-vortex  
macOS bundle: `io.vectorvortex.game`  
Runtime: macOS 14+  
SDKs: SwiftUI, SpriteKit, AVFoundation, AppKit

## Distributable artifacts

The repository's `.github/workflows/release.yml` is configured for a signed and notarized **GitHub Release** when a `v*` tag is pushed. For this game the output contract is `VectorVortex-macOS.zip` and `VectorVortex-macOS.zip.sha256`, with the bundle ID `io.vectorvortex.game`. Fun City's installer discovers this game's latest release via the official `peter-dietrich/vector-vortex` GitHub Releases API and expects these files in the individual game repository.

**Unsigned CI builds** are for development, not a generally trusted public installer. Code signing and notarization are separate steps, not implied by GitHub Actions success.

## Apple signing requirements

A paid Apple Developer Program membership and Developer ID Application certificate are needed for Developer ID distribution. The workflow expects secrets `APPLE_DEVELOPER_ID_CERT_BASE64`, `APPLE_DEVELOPER_ID_CERT_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`. These are credentials, not project files; do not commit them to Git.

## Release procedure

1. Confirm `main` has passed CI; complete Mac interactive, licensing and asset-provenance checks.
2. Verify Apple Developer membership and GitHub Actions secrets are configured and accurate.
3. Verify the game bundle ID and ZIP asset names. Create a version tag only for an approved commit: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Inspect signed build, hardened runtime, notarization receipt and staple status in Actions. Confirm the GitHub Release exposes the matching ZIP and SHA-256 sidecar.
5. On a clean Mac, download and verify SHA-256, code signature, notarization/Gatekeeper and launch behavior.
6. Open Fun City, select the matching cabinet and verify its official release download and install behavior.

**Gate:** without paid signing membership/credentials, keep using local Xcode/unsigned CI builds and do not tag a public release expecting notarization to succeed. This document does not assert that any release is currently signed.
