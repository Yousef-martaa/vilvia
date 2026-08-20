# Android Release Builds

## Why this exists

A production-readiness audit found that Android release builds were signed
with the debug keystore (`android/app/build.gradle.kts`'s stock
`flutter create` default). This is the untouched scaffold default, not a
deliberate choice -- see Issue #79. Release builds are now signed only from
`android/key.properties`, a local, gitignored file, and **fail immediately**
if it's missing, rather than falling back to debug signing or producing an
unsigned artifact.

## One-time setup: generating an upload keystore

You only need to do this once per person/team who will produce signed
release builds. The resulting file is a real secret -- treat it like a
password, not like source code.

```bash
keytool -genkey -v \
  -keystore /path/outside/this/repo/vilvia-upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

`keytool` ships with the JDK (the same one Flutter/Android Studio already
use). You'll be prompted for a store password, a key password (can match the
store password), and some certificate identity fields -- the identity fields
don't matter much beyond record-keeping.

**Store the resulting `.jks` file outside this repository entirely** -- not
just gitignored inside it, but in a password manager, a secrets vault, or
another secured location outside the project directory. This is
belt-and-suspenders against a future `.gitignore` edit or a forced
`git add -f` ever picking it up. Back it up: losing this file before
enrolling in Play App Signing (see below) means you can never update the app
again under the same listing.

## `key.properties` setup

Copy the template and fill in your real values:

```bash
cp android/key.properties.example android/key.properties
```

Edit `android/key.properties`:

```properties
storePassword=<your store password>
keyPassword=<your key password>
keyAlias=upload
storeFile=/absolute/path/to/vilvia-upload-keystore.jks
```

`android/key.properties` is already gitignored (`android/.gitignore`) --
verify with `git status` that it never shows up as a change to commit.

## What must never be committed

- `android/key.properties` (the real one -- `android/key.properties.example`
  with blank placeholders is fine and *is* committed)
- The `.jks`/`.keystore` file itself, anywhere
- Store/key passwords or the key alias, in any file, commit message, issue,
  or log
- A description of exactly where the keystore lives on disk, if that
  location itself is sensitive

## Play App Signing / upload key context

When you enroll in [Play App
Signing](https://support.google.com/googleplay/android-developer/answer/9842756)
(the default and recommended path for new apps in Play Console), the
keystore configured here becomes your **upload key**, not your app's real
signing key. You use it to sign the AAB you upload; Google verifies that
signature, then **re-signs the app with a separate key it manages** before
distributing it to users. Practically, this means:

- If the upload key is ever lost or compromised, Google has a documented
  [key-reset process](https://support.google.com/googleplay/android-developer/answer/9842756#reset)
  -- it's recoverable, unlike the pre-Play-App-Signing model where losing
  your only key meant permanently losing the ability to update the app.
- Still back it up and keep it secret. A reset is a real, disruptive,
  identity-verification-gated process, not a convenience button.
- Nothing about the Gradle configuration in this repo changes whether or not
  you've enrolled in Play App Signing -- it only affects what Google does
  with the AAB after you upload it.

## Building a release

Google Play expects an Android App Bundle, not a raw APK:

```bash
flutter build appbundle --release
```

(`flutter build apk --release` also works, e.g. for manual sideload testing,
and is signed/validated the same way.)

## Expected fail-fast behavior

With `android/key.properties` **absent** (the default state on a fresh
checkout, and the normal state for anyone not producing a signed release):

- `flutter build apk --debug` / `--profile` -- **succeed**, unaffected.
- `flutter build apk --release`, `flutter build appbundle --release`, or
  `flutter run --release` -- **fail immediately** with:

  ```
  Release build requested, but android/key.properties is missing.
  Release builds must be signed with a real upload keystore -- they never
  fall back to debug signing.
  See docs/RELEASE.md and android/key.properties.example to set this up.
  ```

  This is a Gradle configuration-time failure, not a signing error deep in
  the build -- it happens before any compilation or signing is attempted.

With `android/key.properties` present and correctly filled in, release
builds are signed with your real upload key and debug/profile builds are
completely unaffected.

## Manually verifying a release build's signature

After `flutter build apk --release`, confirm the resulting APK is signed
with your real key and not the debug key:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

(`apksigner` ships with the Android SDK build-tools, alongside `keytool`.)
Compare the printed certificate fingerprint (SHA-256) against your upload
key's fingerprint:

```bash
keytool -list -v -keystore /path/to/vilvia-upload-keystore.jks -alias upload
```

They should match. As a sanity check that it's specifically *not* the debug
key, the default debug keystore's fingerprint can be printed the same way
(its store/key password is the well-known default `android`):

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

The two fingerprints must differ.
