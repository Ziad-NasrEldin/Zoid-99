# Zoid 99 macOS releases

Zoid 99 is packaged as a native macOS application from the Swift Package executable.
The release scripts do not store Apple credentials, certificate material, or notarization secrets in the repository.

## Fixed application identity

- Product name: `Zoid 99`
- Executable: `Zoid99`
- Bundle identifier: `com.ziadnasreldin.zoid99`
- Minimum macOS version: 14.0
- Category: Productivity
- Icon source: `Resources/AppIcon.svg`
- Release entitlements: no special entitlements

The empty entitlement set is intentional.
The current product uses outbound networking, local Application Support storage, Keychain access, and user-approved notifications, none of which needs a special entitlement for a directly distributed macOS application.
App Sandbox is not enabled because enabling it later would change the application container and local persistence location.

## Reproducible unsigned build

Use a clean checkout with the Xcode Command Line Tools selected.

```sh
ZOID99_VERSION=0.1.0 ZOID99_BUILD_NUMBER=1 ./scripts/build-release.sh
./scripts/verify-release.sh ".build/release-artifacts/Zoid 99.app"
```

The build creates:

- `.build/release-artifacts/Zoid 99.app`
- `.build/release-artifacts/Zoid-99-0.1.0-unsigned.zip`
- `.build/release-artifacts/Zoid-99-0.1.0-unsigned.zip.sha256`

The application executable is a universal binary for Apple silicon and Intel Macs.
The script normalizes bundle timestamps with `SOURCE_DATE_EPOCH`, which defaults to `2026-01-01T00:00:00Z`.
Set that variable to the source commit time when producing an official release.
Swift compiler and SDK versions still affect the binary.
Record `swift --version` and `xcodebuild -version` in each release record.
Build twice on the same release machine and compare the archive checksums before publishing.

## Apple inputs required for distribution

The release owner must provide these outside the repository:

- An active Apple Developer Program membership.
- A registered App ID matching `com.ziadnasreldin.zoid99`.
- A `Developer ID Application` certificate installed in the signing Keychain.
- The exact certificate name in `ZOID99_SIGNING_IDENTITY`.
- An App Store Connect issuer ID and API key, or an Apple ID app-specific password.
- A `notarytool` Keychain profile created locally and named in `ZOID99_NOTARY_PROFILE`.

Create the local notary profile once with Apple's `xcrun notarytool store-credentials` command.
Do not put its password, private key, or exported certificate in this repository.

## Sign, harden, and notarize

Start from a verified unsigned application.

```sh
export ZOID99_SIGNING_IDENTITY="Developer ID Application: Legal Name (TEAMID)"
export ZOID99_NOTARY_PROFILE="zoid99-notary"
./scripts/sign-and-notarize.sh ".build/release-artifacts/Zoid 99.app"
```

The signing script enables Apple's hardened runtime, applies the least-privilege entitlement file, requests a trusted timestamp, verifies the signature, submits a ZIP to Apple, waits for Apple's result, staples the ticket, and verifies Gatekeeper again.
The script exits on any rejected or incomplete Apple response.
A local build or ad-hoc signature is never evidence of notarization.

## Update delivery

The first public release should be delivered as the notarized and stapled ZIP produced by the signing script.
Publish its `.sha256` file beside it and record the version, build number, Git commit, Swift version, Xcode version, notarization submission ID, and final SHA-256.

Zoid 99 does not currently include an automatic updater.
Do not add a custom updater or silent download mechanism.
A later issue may add a maintained update framework such as Sparkle, including signed update metadata and rollback handling.
Until then, updates are explicit user-installed releases from the project's trusted release location.

## Release verification checklist

- Run `swift test`.
- Run the release build and `scripts/verify-release.sh`.
- Launch the built application and verify the name and icon in native macOS UI.
- Complete the existing manual product checklist without changing app behavior.
- Confirm `codesign --verify --deep --strict` passes after signing.
- Confirm `spctl --assess --type execute` accepts the signed application.
- Confirm `notarytool` reports `Accepted`.
- Confirm `stapler validate` succeeds without a network dependency.
- Compare the published archive checksum with the release record.
- Keep Apple evidence with the release record before stating that a build is notarized.
