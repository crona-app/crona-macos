# Release

## Overview

Crona for macOS is released independently from the core Crona daemon and TUI.

The release workflow is defined in [`.github/workflows/release.yml`](../.github/workflows/release.yml). It builds a universal macOS app, signs it with Developer ID, notarizes it, packages DMG and ZIP artifacts, publishes a GitHub release, and updates the Sparkle appcast on GitHub Pages.

Curated release bodies live in:

- `docs/release-notes/<tag>.md`

If the matching file exists, the release workflow publishes that body instead of generated GitHub notes.

## Channels

- stable tags use `vX.Y.Z`
- beta tags use `vX.Y.Z-beta.N`
- beta installations receive beta and stable releases
- stable installations receive stable releases only
- moving from beta to stable does not downgrade the installed app

The signed Sparkle appcast is published at:

- <https://crona.work/updates/mac/appcast.xml>

Installed apps read that crona.work address, which redirects (302) to the GitHub Pages feed this
workflow deploys (`<owner>.github.io/crona-macos`). If the repository moves, change only the
redirect target in the site repository's `public/_redirects`; never change `SUFeedURL`.

## Release Artifacts

Every stable and beta GitHub release publishes:

- `Crona-<version>-macOS.dmg`
- `Crona-<version>-macOS.zip`
- `Crona-<version>-dSYMs.zip`
- `checksums.txt`

The DMG is the manual install artifact. The ZIP is consumed by Sparkle.

## One-Time Repository Setup

Enable GitHub Pages with GitHub Actions as the source.

Repository variable:

- `SPARKLE_PUBLIC_ED_KEY`

Repository secrets:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_PASSWORD`
- `RELEASE_KEYCHAIN_PASSWORD`
- `APPLE_NOTARY_API_KEY_P8`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `SPARKLE_EDDSA_PRIVATE_KEY`

Generate the Sparkle key pair once with Sparkle's `generate_keys` tool. Store the public key in the repository variable and the private key in the repository secret. Keep the same key for future releases.

## 1.1.0 beta preparation

The next planned release is `v1.1.0-beta.7`, with marketing version `1.1.0`, build `25`, and semantic release version `1.1.0-beta.7`. It requires daemon protocol `1.7`, unchanged from beta.6.

Release notes are prepared in [`docs/release-notes/v1.1.0-beta.7.md`](release-notes/v1.1.0-beta.7.md), with a matching changelog entry. The changelog date reflects this preparation date; update it if publication happens on a later day.

This preparation is documentation-only. Project metadata remains at build `24`; bump `CURRENT_PROJECT_VERSION` to `25` before cutting the release. No release commit or tag is part of this preparation.

Build numbers continue across marketing versions: 1.0.0 used build `18`; 1.1.0 betas 1 through 6 used builds `19` through `24`. Build `25` continues that sequence to preserve Sparkle appcast ordering.

The Debug unit suite passed all 492 tests during development. Release-optimized validation is still required before tagging; memory savings have not been quantified in a before/after Release measurement.

## Cutting a Release

1. Set `MARKETING_VERSION` to the tag's numeric `X.Y.Z` portion.
2. Increment `CURRENT_PROJECT_VERSION`.
3. Add the release entry to `docs/changelog.md` and create `docs/release-notes/<tag>.md`.
4. Run the macOS unit suite with Release optimization and testability enabled:
   `xcodebuild -project crona.xcodeproj -scheme crona -configuration Release CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES test -destination "platform=macOS" -enableCodeCoverage NO -only-testing:cronaTests`.
   For protocol releases, also run the matching core Crona tests and verify the documented protocol version and event contract.
5. Commit the version metadata and release documentation.
6. Create and push the tag.

Example tags:

- `v1.2.3`
- `v1.2.3-beta.1`

The workflow validates:

- tag format
- `MARKETING_VERSION` matches the base version
- `CURRENT_PROJECT_VERSION` is numeric
- `CURRENT_PROJECT_VERSION` is newer than the latest appcast build
- Sparkle public key exists and decodes correctly

The CI workflow in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs the macOS unit suite for pushes to `main` and pull requests targeting `main`.

## Packaging and Signing

The workflow:

- resolves Swift package dependencies
- builds the Release-optimized test products without launching GUI XCTest infrastructure before accessing signing credentials
- imports the Developer ID certificate into a temporary keychain
- archives a universal app for `arm64` and `x86_64`
- injects `CRONA_RELEASE_CHANNEL` and full `CRONA_RELEASE_VERSION`
- exports the signed app
- notarizes and staples the app
- installs pinned `dmgbuild==1.6.7`
- builds the Sparkle ZIP, a branded drag-install DMG, and dSYM archive
- signs, notarizes, staples, mounts, and validates the DMG

Validation includes:

- code signature integrity
- notarization tickets
- universal architectures
- bundle identifier `com.webxsid.crona`
- `CFBundleShortVersionString`
- embedded `CRONA_RELEASE_VERSION`
- embedded `SUPublicEDKey`
- DMG contents, `/Applications` symlink, and branded DMG presentation generated by `dmgbuild`

## Local Validation

You can validate a release DMG locally with:

```sh
codesign --verify --strict --verbose=2 Crona-<version>-macOS.dmg
xcrun stapler validate Crona-<version>-macOS.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 \
  Crona-<version>-macOS.dmg
```

## Distribution Notes

Homebrew distribution remains limited to the Crona terminal utility. The native macOS app is distributed through the DMG and updated through Sparkle.

## Recovering appcast deployment

If a release publishes successfully but Pages deployment fails, run the **Recover macOS appcast deployment** workflow with the original release workflow run ID. It restores the already-signed feed artifact and deploys it without rebuilding or replacing the release assets. Both workflows wait for the uploaded Pages artifact to become visible before deployment.
