Status: needs-info

# Prepare the signed macOS release

Complete app identity, icon, entitlements, hardened runtime, signing, notarization, packaging, and update delivery.
The Apple Developer account and release identity are required before final verification.

## Release 0.2.0 evidence

The reproducible universal arm64 and x86_64 package has bundle identifier `com.ziadnasreldin.zoid99`, version `0.2.0`, build `2`, the `zoid99` deep-link scheme, an explicit entitlements file, and hardened-runtime signing configuration.
The packaged app launches and native proof is stored in `docs/proof/release-0.2.0-packaged-app.jpeg`.
The unsigned ZIP is stored at `.build/release-artifacts/Zoid-99-0.2.0-unsigned.zip`.

## External blocker

No Developer ID Application identity or `ZOID99_NOTARY_PROFILE` was available.
The available Apple Development identity is not a valid substitute for distribution signing and notarization.
Notification permission acceptance must be repeated with the signed, notarized, installed build.
