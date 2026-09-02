#!/bin/zsh
# ============================================================
#  F.R.I.D.A.Y. Vault iOS — Export und Upload nach TestFlight
#  Fassung 1 · 02.09.2026
#
#  Das Archiv ist schon gebaut (build/pbmedia-release/*.xcarchive).
#  Dieses Skript exportiert es als App-Store-IPA und laedt es hoch.
#
#  Signiert wird in der Cloud ueber das in Xcode angemeldete Konto —
#  kein lokaler Verteilungsschluessel, kein Keychain-Dialog. Voraussetzung
#  (seit 02.09.): in der Login-Keychain liegt KEIN lokales Apple-Distribution-
#  Zertifikat mit privatem Schluessel, sonst greift Xcode dorthin und fragt.
# ============================================================
set -uo pipefail
cd "$(dirname "$0")"

ARCHIVE="$(ls -dt build/pbmedia-release/FRIDAY-Vault-*.xcarchive 2>/dev/null | head -1)"
if [[ -z "$ARCHIVE" ]]; then
  echo "ABBRUCH: kein Archiv unter build/pbmedia-release/. Zuerst archivieren:"
  echo "  xcodebuild archive -workspace Bitwarden.xcworkspace -scheme Bitwarden -configuration Release \\"
  echo "    -destination 'generic/platform=iOS' -archivePath build/pbmedia-release/FRIDAY-Vault-<version>-<build>.xcarchive \\"
  echo "    -derivedDataPath \"\$HOME/Library/Caches/FRIDAYVaultiOS-Release\" \\"
  echo "    CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=GCPHB9Z9H4 -allowProvisioningUpdates"
  echo "  (Bauordner NICHT unter Documents — dort bricht Xcode mit 'disk I/O error' ab.)"
  read -n 1 -s -r; exit 1
fi
NAME="$(basename "$ARCHIVE" .xcarchive)"
EXPORT="build/pbmedia-release/${NAME}-export"
echo "Archiv:  $ARCHIVE"
echo "Export:  $EXPORT"
echo
echo "── 1. Export (App-Store-IPA, automatische Signierung) ──"
echo "   Cloud-Signierung ueber das Xcode-Konto, kein Dialog."
rm -rf "$EXPORT"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
     -exportOptionsPlist Configs/ExportOptions-PBMedia-AppStore-Automatic.plist -allowProvisioningUpdates; then
  echo "ABBRUCH: Export rot."; read -n 1 -s -r; exit 1
fi
IPA="$(find "$EXPORT" -maxdepth 1 -name '*.ipa' | head -1)"
[[ -n "$IPA" ]] || { echo "ABBRUCH: keine .ipa im Export."; read -n 1 -s -r; exit 1; }
echo "OK      $IPA"
echo
echo "── 2. IPA pruefen ──"
PBMEDIA_ALLOW_XCODE_MISMATCH=1 PBMEDIA_SIGNING_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db" \
  Scripts/pbmedia_release.sh verify-ipa "$IPA" || echo "HINWEIS: verify-ipa meldet Abweichungen (Profilname ist bei automatischer Signierung ein anderer) — Signatur und Bundle-IDs oben pruefen."
echo
echo "── 3. Upload nach App Store Connect ──"
echo "   Schluessel 7NL8XN2Y2T (darf hochladen). Das dauert ein paar Minuten."
if xcrun altool --upload-app -f "$IPA" -t ios --apiKey 7NL8XN2Y2T --apiIssuer 46b9f7df-7d47-472a-8fb9-4043813e2c8a; then
  echo
  echo "HOCHGELADEN. Apple verarbeitet den Build jetzt (10–30 Minuten); danach steht er in"
  echo "App Store Connect › TestFlight. Bei „Fehlende Exportkonformitaet“ dort einmal beantworten."
else
  echo "ABBRUCH: Upload rot."
fi
echo
read -n 1 -s -r -p "Taste druecken zum Schliessen…"
echo
