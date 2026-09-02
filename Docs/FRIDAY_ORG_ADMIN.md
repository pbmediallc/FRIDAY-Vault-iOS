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

## TestFlight — so ging es am 02.09.2026 (Build 1.1.0 / 2026090201)
- App-Datensatz `com.pbmedia.fridayvault.ios` (ASC-ID 6805077297). Vorher drei Builds (25./26.08.).
- **Signierung:** Cloud-Signierung über das in Xcode angemeldete Konto (Zertifikat vom 13.08.,
  ohne lokalen Schlüssel). Dafür musste das lokale Zertifikat vom 29.08. aus der Login-Keychain —
  Patrick hat es selbst entfernt (`security delete-certificate -Z 6322C9…`). Solange ein lokales
  Apple-Distribution-Zertifikat mit privatem Schlüssel in der Keychain liegt, wählt Xcode es und
  verlangt aus der Kommandozeile einen Keychain-Dialog. Der ASC-Schlüssel 7NL8XN2Y2T darf keine
  Profile anlegen (403) — Cloud-Signierung über den Schlüssel geht deshalb nicht.
- **Archiv:** `xcodebuild archive … CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=GCPHB9Z9H4
  -allowProvisioningUpdates -derivedDataPath ~/Library/Caches/FRIDAYVaultiOS-Release`.
  Bauordner nicht unter Documents (synchronisiert): dort `disk I/O error` in der build.db.
- **Export:** `Configs/ExportOptions-PBMedia-AppStore-Automatic.plist` (app-store-connect, automatic).
- **Upload:** `xcrun altool --upload-app … --apiKey 7NL8XN2Y2T --apiIssuer 46b9f7df-…`.
- **Exportkonformität:** Apple lehnte den ersten Upload ab (90592, kein Code in der Info.plist).
  Alle bisherigen Builds liefen mit `ITSAppUsesNonExemptEncryption = false`; darauf zurückgestellt.
- `TESTFLIGHT-HOCHLADEN.command` bündelt Export, Prüfung und Upload für das jüngste Archiv.
- Offen laut `PBMEDIA_APP_STORE_RELEASE.md`: GPL-Quelltext des exakten Builds veröffentlichen.
