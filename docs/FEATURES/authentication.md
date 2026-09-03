# Authentication

## Why authentication?

Most of the content in Vilvia should be available without requiring users to create an account.

The goal is to make it as easy as possible for new parents to access reliable information without adding unnecessary steps.

An account only becomes necessary when a user wants to participate in the community or personalize their experience.

---

## What can users do without an account?

Visitors can:

- Read parenting articles
- Browse categories
- Search for information
- View public community discussions
- Explore the app

---

## When is sign-in required?

Users need an account when they want to:

- Create a post
- Leave comments
- Like or save content
- Manage their profile and personalization settings
- Access personalized content and future features

---

## Authentication method (MVP)

For the first release, authentication will be kept simple.

Supported methods:

- Email and password

Additional sign-in methods such as Google, Apple, or BankID may be added later if there is a clear need.

---

## Registration data

During registration, users will provide:

- First name
- Email address
- Password

After registration, users will complete a short onboarding process to personalize their experience.

Additional profile information can be added later without changing the authentication flow.

---

## Notes

Authentication should stay as simple as possible.

The purpose is to support the experience, not become a barrier before parents can start using the app.

---

## Implementation (Issue #67)

Email/password via Supabase Auth, verified backend-side using the project's
public JWT signing keys (JWKS) -- no service-role/secret key involved.
`get_current_user` verifies a token (signature, issuer, expiry, audience,
and that it's an ordinary authenticated-user session, not an anon/service
key) and returns that identity only; it never touches the database.

Profile provisioning is a separate, explicit step: `POST /me/bootstrap`
creates the caller's `Profile` (id and email from the verified identity,
first name from the request body, role always `parent`) if one doesn't
exist yet, and is safe to call more than once. `GET /me` is read-only and
returns 404 if no Profile exists yet -- it never creates one.

Home, Resources, and Events remain fully usable without signing in.

Still not implemented: password reset, email change, social login, MFA,
profile editing, and no existing screen is gated behind authentication.

The durable backend account-deletion request, in-app confirmation flow, local
sign-out after acceptance, and asynchronous operator fulfillment workflow are
documented separately in `docs/FEATURES/account_deletion.md`. The external HTTPS
request resource remains a separate release requirement.
Because JWT leeway applies to both a future `iat` and an expired `exp`, completed
deletion records are retained for at least the configured maximum token
lifetime plus twice the configured clock skew.

---

## Implementation (Issue: harden authentication and profile foundation)

### Gender is a profile attribute, not an authorization role

`Profile.gender` (`male`/`female`) and `Profile.role` (`parent`/`admin`)
are separate columns backed by separate enums (`Gender`, `UserRole` in
`app/models/enums.py`). `gender` must never be used to grant or deny
access to anything, and `role` must never be derived from it. A public
signup always gets `role = parent`; there is no field on any request
schema that can set `role`, so there is no mass-assignment path to
`admin`.

### Migration compatibility: nullable column, required for new signups

`profiles.gender` is a **nullable** database column (migration
`7101b67a47b8_add_profile_gender`), so existing rows created before this
field existed are left as `gender = NULL` rather than being backfilled
with a fabricated value.

New profiles are different: `BootstrapRequest.gender` is a **required**
field, validated as a `Gender` enum by Pydantic, so `POST /me/bootstrap`
rejects a missing or invalid value with `422` before ever reaching the
database. This split -- nullable at the schema layer, required at the
application layer for new writes -- means:

- Old accounts can keep working indefinitely with `gender = null` in
  `GET /me`'s response.
- Every *newly created* profile always has a real value.
- No backfill migration or "complete your profile" flow for legacy NULL
  rows is implemented in this issue -- deliberately deferred until there
  is a concrete feature that needs it, per the product's
  collect-only-what's-needed principle.

### Admin authorization boundary

`app/api/deps.py` provides `require_admin`, a dependency (not a
permissions framework) that resolves the caller's `Profile` from the
already-verified identity (`get_current_user` + `get_db`) and requires
`role == UserRole.admin`, returning `403` for a non-admin *or* a missing
Profile -- it never distinguishes the two to the client. It takes no
role/id input from the request itself, so a client cannot assert its own
admin status. No endpoint uses it yet; it exists so the first privileged
endpoint can `Depends(require_admin)` directly. Admin elevation itself
remains a manual, trusted operation (e.g. a direct database update by an
operator) -- there is no self-service or API path to become an admin.

### Security logging

Minimal, deliberately narrow logging was added where it has real
investigative value, and nowhere else:

- `require_admin` logs a warning (caller id only) when access is denied
  -- a signal worth watching for privilege-escalation attempts.
- `POST /me/bootstrap` logs an info line (caller id only) when it
  actually creates a new profile, and a warning on the email-conflict
  (`409`) path.

Deliberately *not* logged: passwords, access/refresh tokens, API
keys/secrets, JWT claims, or email addresses in these log lines. Routine
JWT verification failures (e.g. an expired session, which is normal,
frequent, benign traffic) are not logged, to avoid noise that would bury
genuinely actionable signals. Clients never receive verification
details either way -- `InvalidTokenError` collapses every failure reason
into one generic `401`.

### What's controlled where

- **This repository**: identity always comes from a verified JWT never
  trusted client input; no mass-assignment path to `role`; `gender`
  validated server-side via Pydantic/enum; no password handling of any
  kind (Supabase owns that entirely); minimal, secret-free logging as
  above.
- **Supabase Dashboard configuration** (not code, not verified from this
  repo -- confirm directly in the project's dashboard): minimum password
  length, "Confirm email", leaked-password protection, rate limits, and
  CAPTCHA/bot protection. See the issue's investigation report for
  specific recommended values.
- **Deferred to a future issue, not a blocker here**: CAPTCHA UI wiring
  (needs a new Flutter dependency).

No blanket "OWASP compliant" or "secure against the OWASP Top 10" claim
is made here -- the above is the specific, verifiable set of controls
this issue establishes, not a general security guarantee.

---

## Implementation (Issue #85): secure on-device session storage

### Why

A production-readiness audit found that Supabase's default session
storage on Android (`SharedPreferencesLocalStorage`) persists the access
and refresh tokens as **plaintext** in an app-private XML file. That's
protected only by normal Android per-app sandboxing, not by any
app-level encryption -- readable on a rooted device, via `adb`-based
extraction on a debuggable build, or from a lost/stolen device's
storage.

### What changed

`lib/main.dart` now passes `authOptions:
FlutterAuthClientOptions(localStorage: SecureLocalStorage(...))` to
`Supabase.initialize`, replacing the SDK's default. `SecureLocalStorage`
(`lib/core/storage/secure_local_storage.dart`) implements Supabase's own
5-method `LocalStorage` interface, backed by
[`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
11.0.0 with its current default `AndroidOptions()` -- RSA-OAEP key
wrapping (Android Keystore-backed, non-exportable) + AES-GCM data
encryption. This is **not** the deprecated Jetpack Security
`encryptedSharedPreferences` option (removed from the package as of
v10) -- no custom crypto was written for this; the encryption itself is
entirely the maintained package's responsibility. `flutter_secure_storage`
is cross-platform by design: the same Dart code will use iOS Keychain
automatically once an iOS target exists in this repo (there isn't one
yet), with no platform-conditional code needed here.

`AuthService`, every auth screen, `ProfileApiClient`, and the backend's
JWT verification are all unchanged -- this is purely a storage-backend
swap behind `LocalStorage`'s existing opaque-string interface. Session
restoration, token refresh, sign-in, sign-up, and logout all behave the
same as before from the app's perspective; only *where* the session
lives on disk changed.

### One-time migration from the legacy plaintext session

Devices that already had a signed-in session under the SDK's previous
default storage are migrated automatically, once, the first time the
app runs after this change (`SecureLocalStorage.initialize()`, called
during `Supabase.initialize`):

1. Read the legacy session string via Supabase's own
   `SharedPreferencesLocalStorage` (not a reimplementation of
   SharedPreferences access) -- the string is treated as fully opaque,
   never parsed or reconstructed.
2. Write that exact string into secure storage.
3. Read it back and confirm it matches what was written.
4. Only then delete the legacy plaintext entry.

If the secure write throws, or the read-back doesn't match, the legacy
value is left untouched rather than risking data loss -- migration
simply retries on the next app launch. Nothing about the session or
token contents is ever logged at any step. A device with no legacy
session (a fresh install, or one already migrated) is a no-op.

**User-visible effect**: a user with an existing session gets migrated
silently and stays signed in. In the rare case the legacy read or the
secure write genuinely fails, the user is signed out once and simply
signs back in -- there is no data corruption or crash, only a fallback
to the normal sign-in flow.

### Failure behavior

Reads from secure storage (`accessToken()`, `hasAccessToken()`) catch
`PlatformException` specifically -- not a blanket exception handler --
and treat it as "no persisted session" rather than crashing. This is the
same outcome a user would see from a normal logged-out state; it isn't
distinguished as an error state anywhere the user can see.

### Android backup behavior

Android's Auto Backup (device-to-device transfer and cloud backup) is
**not** disabled app-wide (`android:allowBackup` is left at its
platform default). Instead, `android/app/src/main/AndroidManifest.xml`
narrowly excludes only the two SharedPreferences files
`flutter_secure_storage` 11.0.0 uses on Android --
`FlutterSecureStorage` and `FlutterSecureKeyStorage`, confirmed from the
installed package's own Android source
(`FlutterSecureStorageConfig.java`, `FlutterSecureStorage.java`) -- via
`android:dataExtractionRules` (API 31+) and `android:fullBackupContent`
(API 23-30), see `android/app/src/main/res/xml/data_extraction_rules.xml`
and `backup_rules.xml`.

This exists because the RSA key used to unwrap stored secrets is
Keystore-bound and never transfers with a backup -- restoring these
files onto a different device/Keystore would make them permanently
undecryptable (and can throw `InvalidKeyException` before this app's
own fail-safe reads even get a chance to handle it gracefully). The
narrow exclusion was chosen over the blanket `allowBackup="false"` flag
because Vilvia currently has no other local persistence that would
benefit from Auto Backup, so there's no product-impact reason to
disable it app-wide, and this keeps Auto Backup available for anything
the app may persist locally in the future.

### Logout

`AuthService.signOut()` is unchanged -- it still calls
`GoTrueClient.signOut()`, which internally calls the configured
`LocalStorage.removePersistedSession()`. That now deletes the entry
from secure storage instead of SharedPreferences, so logout removes the
persisted session the same way it always did, just from the new
storage.
