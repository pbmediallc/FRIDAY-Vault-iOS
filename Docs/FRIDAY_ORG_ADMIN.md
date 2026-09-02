# F.R.I.D.A.Y. Vault iOS — Organisationsverwaltung (Stand 02.09.2026)

Einstieg: **Einstellungen › Organisationen**. Zeigt die Organisationen des angemeldeten
Kontos; Antippen öffnet die Admin Console mit den Chips Sammlungen · Mitglieder ·
Gruppen · Berichte · Richtlinien · Einstellungen — in der Formsprache der Loginmaske.

## Aufbau
- `BitwardenShared/Core/Platform/FridayOrg/`
  - `FridayOrgModels.swift`, `FridayOrgParser.swift`, `FridayOrgCrypto.swift` — wörtlich
    aus der Mac-App (FRIDAY-Vault, dort mit Referenzvektoren geprüft).
  - `FridayOrgClient.swift` — Bitwarden-Organisations-API über den `HTTPService` der App
    (Token und 401-Erneuerung kommen von der App, kein zweiter Schlüssel).
  - `FridayOrgEngine.swift` — `FridayOrgVaultEngine`: Sammlungsnamen ver-/entschlüsselt das
    Bitwarden-SDK; Bestätigen verpackt den Organisationsschlüssel
    (Nutzerschlüssel → privater RSA-Schlüssel → Org-Schlüssel, dann RSA-OAEP-SHA1 für das
    Mitglied); Einträge über `VaultRepository` (shareCipher, updateCipherCollections,
    softDelete, restore). `FridayOrgCryptoTests.swift` läuft im Testziel mit.
  - `FridayOrgStore.swift` — Zustand je Organisation; jede Schreibaktion: ausführen →
    neu laden → Wirkung prüfen, sonst „nicht nachweisbar".
- `BitwardenShared/UI/Platform/FridayOrg/` — `FridayAdminDesign.swift` (Avatar-Zeilen,
  Karten, Chips, Menü als Blatt von unten, Dialograhmen), `FridayOrgAdminView.swift`,
  `FridayOrgSheets.swift`.
- Einhängung: `SettingsRoute.organizations`, `SettingsAction.organizationsPressed`,
  `SettingsCoordinator.showOrganizations()`, Zeile in `SettingsView`.

## Fallen
- `@State` ist im Modul verschattet → `@SwiftUI.State`.
- SwiftLint bricht den Bau bei Dateilänge/Typlänge → Kopfzeile `swiftlint:disable`.
- `presentationDetents` erst ab iOS 16 → `fridayHalfSheet()`.
- Simulator-Bau nur signiert starten; unsigniert fehlen die Entitlements und die App
  beendet sich beim Keychain-Zugriff.

## TestFlight
- App-Datensatz `com.pbmedia.fridayvault.ios` (ASC-ID 6805077297) existiert.
- Die App-Store-Profile vom 31.07. hängen an einem Zertifikat ohne privaten Schlüssel
  (gesperrte Keychain). Nur `Apple Distribution: PB Media LLC` vom 29.08. (6322C9…) hat
  einen — deshalb automatische Signierung:
  `xcodebuild archive … CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=GCPHB9Z9H4 -allowProvisioningUpdates`
  (Archiv 1.1.0 / 2026090201 liegt unter `build/pbmedia-release/`).
- Der Export signiert mit diesem Schlüssel und verlangt aus der Kommandozeile EINMAL den
  Keychain-Dialog „Immer erlauben" (belegt per `codesign --sign 6322…` → SecurityAgent;
  der Entwicklerschlüssel fragt nicht). Danach: `TESTFLIGHT-HOCHLADEN.command` — Export,
  Prüfung, `altool --upload-app` mit Schlüssel 7NL8XN2Y2T.
- Offen laut `PBMEDIA_APP_STORE_RELEASE.md`: GPL-Quelltext des exakten Builds
  veröffentlichen, Exportkonformität in App Store Connect beantworten.
