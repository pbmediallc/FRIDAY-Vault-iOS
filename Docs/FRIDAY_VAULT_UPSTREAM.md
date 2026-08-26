# F.R.I.D.A.Y. Vault iOS: upstream and licensing notice

F.R.I.D.A.Y. Vault iOS is an independently maintained, modified fork of the
Bitwarden iOS Password Manager. It is not affiliated with, sponsored by, or
endorsed by Bitwarden, Inc. Bitwarden names and marks remain the property of
their respective owners.

PB Media LLC began modifying this fork for F.R.I.D.A.Y. Vault on 19 August
2026. The complete modified work remains licensed under GNU GPL version 3.

## Upstream baseline

- Upstream project: <https://github.com/bitwarden/ios>
- Imported baseline commit: `9ca63ccf7bacf8dcbb96af0a8fa6f7b3d8913a8d`
- Relevant modification date: 2026-08-19
- Modifier: PB Media LLC
- License: GNU General Public License version 3, preserved in `LICENSE.txt`
- Cryptographic engine: the official Bitwarden Swift SDK revision pinned in
  `project-common.yml`; this fork does not replace the vault cryptography with
  a custom implementation.

The original copyright notices, license text, third-party acknowledgements,
and the acknowledgement-generation build step must remain present in all
distributed builds and corresponding source releases.

## Corresponding source

Distribution through TestFlight or another channel must be accompanied by a
GPLv3-compliant way for every recipient to obtain the complete corresponding
source for the exact distributed build, including the build configuration and
the F.R.I.D.A.Y.-specific modifications.

The recorded corresponding-source location for F.R.I.D.A.Y. Vault
`1.0.1 (2026082601)` is the immutable tag:

<https://github.com/pbmediallc/FRIDAY-Vault-iOS/tree/v1.0.1-2026082601>

That exact URL must resolve without authentication and expose the complete
source tree before build `2026082601` is distributed. The stable fork repository
is <https://github.com/pbmediallc/FRIDAY-Vault-iOS>.

## Security boundaries of this fork

- The main app and AutoFill extension use one F.R.I.D.A.Y.-owned App Group and
  one F.R.I.D.A.Y.-owned Keychain access group.
- The master password, decrypted vault items, and session keys must never be
  written to logs, analytics, crash-reporting services, shared defaults, or
  plaintext files.
- Firebase and Crashlytics are intentionally excluded from the F.R.I.D.A.Y.
  build. Local OSLog reporting must not be expanded to include credentials,
  decrypted fields, tokens, or request bodies.
- F.R.I.D.A.Y. signing identifiers, URL schemes, icons, associated domains,
  and App Store metadata must not reuse Bitwarden production identities.
- Changes to branding or transport must not weaken the upstream zero-knowledge
  encryption and key-derivation model.

## Rebase discipline

Future upstream updates should retain this notice, `LICENSE.txt`, the Settings
acknowledgements, the official SDK pin or a deliberately reviewed successor,
the isolated F.R.I.D.A.Y. signing groups, and the no-telemetry security policy.
