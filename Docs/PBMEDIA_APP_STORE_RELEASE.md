# PB Media App Store release path

This is the F.R.I.D.A.Y. Vault-specific release path. Do not use
`Scripts/select_variant.sh` or the upstream `Scripts/build.sh` for a PB Media
release: those scripts still generate Bitwarden-owned identifiers, profile
names, and mutable local configuration.

## Fixed identity

- Team: `GCPHB9Z9H4`
- Main app: `com.pbmedia.fridayvault.ios`
- AutoFill extension: `com.pbmedia.fridayvault.ios.autofill`
- Shared App Group: `group.com.pbmedia.fridayvault.ios`
- App Store profiles:
  - `PB Media F.R.I.D.A.Y. Vault App Store`
  - `PB Media F.R.I.D.A.Y. Vault AutoFill App Store`

The checked-in export options use manual signing and those exact profile
names. The release script never passes `-allowProvisioningUpdates`, so archive
and export cannot create or modify App IDs, capabilities, certificates, or
profiles on Apple's Developer portal.

## Apple resources required before the first archive

Create or verify these resources outside this script:

1. An explicit iOS App ID for `com.pbmedia.fridayvault.ios`.
2. An explicit iOS App ID for `com.pbmedia.fridayvault.ios.autofill`.
3. Enable `APP_GROUPS` and `AUTOFILL_CREDENTIAL_PROVIDER` on both App IDs.
4. Create or verify `group.com.pbmedia.fridayvault.ios` and assign it to both
   App IDs.
5. Create `IOS_APP_STORE` profiles with the two exact names above, using an
   active PB Media Apple Distribution certificate, then install them locally.
6. Create the App Store Connect app record for the main bundle ID. Choose the
   customer-facing name, SKU, primary locale, and access deliberately.

Changing a capability invalidates existing profiles. Configure both IDs and
their App Group assignments before generating the final profiles.

## Current external blockers (read-only snapshot, 2026-08-19)

The App Store Connect API returned no registered Bundle ID for either F.R.I.D.A.Y.
identifier and no app record for the main identifier. Consequently, matching
profiles cannot exist yet. The API did return two unexpired PB Media Apple
Distribution certificate records, expiring 2027-07-31 and 2027-08-13.

The standalone App Group registry is not exposed by the App Store Connect REST
API. Its object therefore still needs portal verification; regardless of
whether it already exists, its assignment to the two currently absent App IDs
is missing.

The custom signing keychain is not currently in the user keychain search list,
and no identity can be read from it while it is unavailable. The release script
will report this and stop. It intentionally never unlocks or changes a
keychain.

The repository requires Xcode 26.5, while the inspected machine currently has
Xcode 26.6 selected. Use Xcode 26.5 for the reproducible release, or set
`PBMEDIA_ALLOW_XCODE_MISMATCH=1` only after explicitly accepting that drift.

## Non-signing gates

- `ITSAppUsesNonExemptEncryption` is `true` in the app and extension. Obtain a
  PB Media export-compliance determination and, if Apple issues one, record the
  F.R.I.D.A.Y.-specific compliance code. Do not reuse Bitwarden's code.
- Before distributing build `1.0.1 (2026081901)`, publish its complete
  corresponding source and verify without authentication that the immutable
  tag URL resolves:
  <https://github.com/pbmediallc/FRIDAY-Vault-iOS/tree/v1.0.1-2026081901>.
  A local Git remote or the Bitwarden upstream repository is not corresponding
  source for the F.R.I.D.A.Y. modifications.
- The absent app record also means App Store/TestFlight metadata is not ready:
  privacy policy and support URLs, App Privacy answers, age rating, review and
  beta contact information, descriptions, screenshots, and tester groups must
  be completed in App Store Connect as applicable.

## Deferred capability gates (decide before the first TestFlight build)

Two upstream capabilities were removed during the F.R.I.D.A.Y. rebrand. Neither
is re-enabled automatically; each needs an explicit decision by the release
owner, because both require Apple-side provisioning that this repository cannot
grant itself.

### Push-driven sync

`aps-environment` was removed from `Bitwarden/Application/Support/Bitwarden.entitlements`
and `UIBackgroundModes: remote-notification` from `Bitwarden/Application/Support/Info.plist`.

- Effect: the vault no longer receives server-initiated sync pushes. Sync happens
  on foreground, on manual pull-to-refresh, and on the existing periodic paths.
- Product acceptance point 1 ("sync") is therefore only satisfiable in the
  foreground sense until this is decided.
- Re-enabling requires the Push Notifications capability on the App ID, an APNs
  key or certificate for the PB Media team, and a Vaultwarden deployment that is
  actually configured to send push notifications. Vaultwarden only relays push
  when it is registered with a Bitwarden push relay, which is a separate
  external dependency.
- Do not re-add the entitlement before that server-side story is settled; an
  `aps-environment` entitlement without a matching App ID capability fails
  provisioning at archive time.

### Associated domains

`com.apple.developer.associated-domains` was removed together with the upstream
`webcredentials:`/`applinks:` entries for the bitwarden.com family.

- Effect: no shared-web-credential association and no universal links. The
  AutoFill Credential Provider extension itself is unaffected and still matches
  by URI according to the vault entries, so product acceptance point 3 stands.
- Re-enabling is only meaningful for domains PB Media actually controls, and
  requires the Associated Domains capability on the App ID plus a served
  `apple-app-site-association` file on each domain.
- Never reintroduce the Bitwarden production domains. They are not PB Media
  identities and reusing them is both incorrect and a trademark problem.

## Local commands after the external gates are complete

First make the dedicated signing keychain available and unlocked outside the
script, without placing a password in shell history. Then run:

```bash
Scripts/pbmedia_release.sh config-check
Scripts/pbmedia_release.sh signing-check
Scripts/pbmedia_release.sh archive
Scripts/pbmedia_release.sh export
Scripts/pbmedia_release.sh verify-ipa \
  build/pbmedia-release/FRIDAY-Vault-1.0.1-2026081901-export/Bitwarden.ipa
```

The default outputs are versioned beneath `build/pbmedia-release/`; existing
archive and export paths are never overwritten. Archive and export are local
operations and do not upload anything.

The `verify-ipa` command checks the version and build, both bundle identifiers,
embedded profiles, `get-task-allow`, the production App Group, the AutoFill
entitlement, and all signatures. Keep the archive for symbolication and perform
any additional product-specific inspection before upload.

Upload is intentionally separate and guarded by the current build number. For
build `2026081901`, the command is:

```bash
PBMEDIA_CONFIRM_UPLOAD=UPLOAD-2026081901 \
  Scripts/pbmedia_release.sh upload \
  build/pbmedia-release/FRIDAY-Vault-1.0.1-2026081901-export/Bitwarden.ipa
```

Do not run the upload command until the App Store Connect app record exists,
the exported IPA has passed inspection, export compliance and GPL source
delivery are resolved, and the release owner has explicitly approved that
specific build. A successful upload is only delivery to Apple; processing,
TestFlight assignment, installation, device testing, and acceptance remain
separate gates.
