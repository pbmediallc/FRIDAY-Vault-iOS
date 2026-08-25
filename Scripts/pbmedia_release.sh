#!/usr/bin/env bash
#
# PB Media release path for F.R.I.D.A.Y. Vault.
#
# This script deliberately does not use -allowProvisioningUpdates and never
# creates or changes Apple Developer resources. Upload is a separate, guarded
# command so archive/export cannot accidentally publish a build.

set -euo pipefail

readonly release_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly release_repo_root="$(cd "${release_script_dir}/.." && pwd)"
readonly release_team_id="GCPHB9Z9H4"
readonly release_main_bundle_id="com.pbmedia.fridayvault.ios"
readonly release_autofill_bundle_id="com.pbmedia.fridayvault.ios.autofill"
readonly release_app_group_id="group.com.pbmedia.fridayvault.ios"
readonly release_main_profile="PB Media F.R.I.D.A.Y. Vault App Store"
readonly release_autofill_profile="PB Media F.R.I.D.A.Y. Vault AutoFill App Store"
readonly release_export_options="${release_repo_root}/Configs/ExportOptions-PBMedia-AppStore.plist"
readonly release_key_id="7NL8XN2Y2T"
readonly release_issuer_id="46b9f7df-7d47-472a-8fb9-4043813e2c8a"
readonly release_api_key_path="${HOME}/.appstoreconnect/private_keys/AuthKey_${release_key_id}.p8"
readonly release_signing_keychain="${PBMEDIA_SIGNING_KEYCHAIN:-${HOME}/Library/Keychains/friday-build-20260731.keychain-db}"

release_info() {
    printf 'PB Media release: %s\n' "$*"
}

release_warn() {
    printf 'PB Media release warning: %s\n' "$*" >&2
}

release_die() {
    printf 'PB Media release error: %s\n' "$*" >&2
    exit 1
}

release_usage() {
    cat <<'USAGE'
Usage:
  Scripts/pbmedia_release.sh config-check
  Scripts/pbmedia_release.sh signing-check
  Scripts/pbmedia_release.sh archive
  Scripts/pbmedia_release.sh export [archive-path]
  Scripts/pbmedia_release.sh verify-ipa <ipa-path>
  PBMEDIA_CONFIRM_UPLOAD=UPLOAD-<build> Scripts/pbmedia_release.sh upload <ipa-path>

Commands:
  config-check   Validate the checked-in PB Media IDs, entitlements, and export plist.
                 This is local, read-only, and does not inspect signing assets.
  signing-check  Additionally require the exact Xcode version, two installed App
                 Store profiles, and an accessible Apple Distribution identity.
                 It never unlocks or changes a keychain.
  archive        Regenerate the ignored Xcode projects, then archive with manual
                 local signing. It never contacts or changes the Developer portal.
  export         Export an existing archive to an IPA using only local signing assets.
  verify-ipa     Inspect an IPA's IDs, version, profiles, entitlements, and signatures.
  upload         Upload one existing IPA with altool. This is the only command that
                 mutates App Store Connect and it requires the exact build guard.

Optional environment:
  PBMEDIA_SIGNING_KEYCHAIN=/absolute/path/to/keychain-db
  PBMEDIA_RELEASE_ROOT=/absolute/path/to/output-directory
  PBMEDIA_ALLOW_XCODE_MISMATCH=1
USAGE
}

release_setting() {
    local release_key="$1"
    awk -v key="${release_key}:" '$1 == key { print $2; exit }' "${release_repo_root}/project-pm.yml"
}

release_require_file() {
    [[ -f "$1" ]] || release_die "required file is missing: $1"
}

release_require_line() {
    local release_expected_line="$1"
    local release_file="$2"
    grep -Fqx "${release_expected_line}" "${release_file}" \
        || release_die "expected line not found in ${release_file}: ${release_expected_line}"
}

release_plist_value() {
    local release_file="$1"
    local release_key_path="$2"
    /usr/libexec/PlistBuddy -c "Print :${release_key_path}" "${release_file}" 2>/dev/null
}

release_require_plist_value() {
    local release_file="$1"
    local release_key_path="$2"
    local release_expected_value="$3"
    local release_actual_value
    release_actual_value="$(release_plist_value "${release_file}" "${release_key_path}")" \
        || release_die "missing plist key ${release_key_path} in ${release_file}"
    [[ "${release_actual_value}" == "${release_expected_value}" ]] \
        || release_die "${release_file}:${release_key_path} is '${release_actual_value}', expected '${release_expected_value}'"
}

release_config_check() {
    local release_main_entitlements="${release_repo_root}/Bitwarden/Application/Support/Bitwarden.entitlements"
    local release_autofill_entitlements="${release_repo_root}/BitwardenAutoFillExtension/Application/Support/BitwardenAutoFill.entitlements"
    local release_main_info="${release_repo_root}/Bitwarden/Application/Support/Info.plist"
    local release_autofill_info="${release_repo_root}/BitwardenAutoFillExtension/Application/Support/Info.plist"
    local release_common_config="${release_repo_root}/Configs/Common-bwpm.xcconfig"
    local release_autofill_config="${release_repo_root}/Configs/BitwardenAutoFillExtension.xcconfig"

    release_require_file "${release_repo_root}/project-pm.yml"
    release_require_file "${release_repo_root}/project-bwk.yml"
    release_require_file "${release_repo_root}/Bitwarden.xcworkspace/contents.xcworkspacedata"
    release_require_file "${release_main_entitlements}"
    release_require_file "${release_autofill_entitlements}"
    release_require_file "${release_main_info}"
    release_require_file "${release_autofill_info}"
    release_require_file "${release_export_options}"

    plutil -lint \
        "${release_main_entitlements}" \
        "${release_autofill_entitlements}" \
        "${release_main_info}" \
        "${release_autofill_info}" \
        "${release_export_options}" >/dev/null

    release_require_line "DEVELOPMENT_TEAM = ${release_team_id}" "${release_common_config}"
    release_require_line "BASE_BUNDLE_ID = ${release_main_bundle_id}" "${release_common_config}"
    release_require_line "SHARED_APP_GROUP_IDENTIFIER = ${release_app_group_id}" "${release_common_config}"
    release_require_line 'PRODUCT_BUNDLE_IDENTIFIER = $(BASE_BUNDLE_ID).autofill' "${release_autofill_config}"

    release_require_plist_value "${release_main_entitlements}" \
        "com.apple.security.application-groups:0" '$(SHARED_APP_GROUP_IDENTIFIER)'
    release_require_plist_value "${release_autofill_entitlements}" \
        "com.apple.security.application-groups:0" '$(SHARED_APP_GROUP_IDENTIFIER)'
    release_require_plist_value "${release_main_entitlements}" \
        "com.apple.developer.authentication-services.autofill-credential-provider" "true"
    release_require_plist_value "${release_autofill_entitlements}" \
        "com.apple.developer.authentication-services.autofill-credential-provider" "true"
    release_require_plist_value "${release_main_entitlements}" \
        "keychain-access-groups:0" '$(AppIdentifierPrefix)$(BASE_BUNDLE_ID)'
    release_require_plist_value "${release_autofill_entitlements}" \
        "keychain-access-groups:0" '$(AppIdentifierPrefix)$(BASE_BUNDLE_ID)'
    release_require_plist_value "${release_main_info}" "ITSAppUsesNonExemptEncryption" "true"
    release_require_plist_value "${release_autofill_info}" "ITSAppUsesNonExemptEncryption" "true"

    release_require_plist_value "${release_export_options}" "method" "app-store-connect"
    release_require_plist_value "${release_export_options}" "destination" "export"
    release_require_plist_value "${release_export_options}" "teamID" "${release_team_id}"
    release_require_plist_value "${release_export_options}" "signingStyle" "manual"
    release_require_plist_value "${release_export_options}" "signingCertificate" "Apple Distribution"
    release_require_plist_value "${release_export_options}" \
        "provisioningProfiles:${release_main_bundle_id}" "${release_main_profile}"
    release_require_plist_value "${release_export_options}" \
        "provisioningProfiles:${release_autofill_bundle_id}" "${release_autofill_profile}"

    local release_marketing_version
    local release_build_number
    release_marketing_version="$(release_setting MARKETING_VERSION)"
    release_build_number="$(release_setting CURRENT_PROJECT_VERSION)"
    [[ -n "${release_marketing_version}" ]] || release_die "MARKETING_VERSION is missing from project-pm.yml"
    [[ -n "${release_build_number}" ]] || release_die "CURRENT_PROJECT_VERSION is missing from project-pm.yml"

    release_info "configuration OK (${release_main_bundle_id} ${release_marketing_version} build ${release_build_number})"
}

release_find_profile() {
    local release_expected_name="$1"
    local release_profile_dir
    local release_profile_path
    local release_profile_name

    for release_profile_dir in \
        "${HOME}/Library/MobileDevice/Provisioning Profiles" \
        "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
        [[ -d "${release_profile_dir}" ]] || continue
        while IFS= read -r -d '' release_profile_path; do
            release_profile_name="$(
                security cms -D -i "${release_profile_path}" 2>/dev/null \
                    | plutil -extract Name raw -o - - 2>/dev/null
            )" || true
            if [[ "${release_profile_name}" == "${release_expected_name}" ]]; then
                printf '%s\n' "${release_profile_path}"
                return 0
            fi
        done < <(find "${release_profile_dir}" -type f -name '*.mobileprovision' -print0)
    done
    return 1
}

release_validate_profile() {
    local release_profile_name="$1"
    local release_expected_app_identifier="$2"
    local release_profile_path
    local release_profile_team
    local release_profile_app_identifier
    local release_profile_group
    local release_profile_autofill
    local release_get_task_allow

    release_profile_path="$(release_find_profile "${release_profile_name}")" \
        || release_die "installed profile not found: ${release_profile_name}"
    release_profile_team="$(
        security cms -D -i "${release_profile_path}" 2>/dev/null \
            | plutil -extract TeamIdentifier.0 raw -o - -
    )"
    release_profile_app_identifier="$(
        security cms -D -i "${release_profile_path}" 2>/dev/null \
            | plutil -extract Entitlements.application-identifier raw -o - -
    )"
    release_profile_group="$(
        security cms -D -i "${release_profile_path}" 2>/dev/null \
            | plutil -extract 'Entitlements.com\.apple\.security\.application-groups.0' raw -o - -
    )"
    release_profile_autofill="$(
        security cms -D -i "${release_profile_path}" 2>/dev/null \
            | plutil -extract 'Entitlements.com\.apple\.developer\.authentication-services\.autofill-credential-provider' raw -o - -
    )"
    release_get_task_allow="$(
        security cms -D -i "${release_profile_path}" 2>/dev/null \
            | plutil -extract Entitlements.get-task-allow raw -o - -
    )"

    [[ "${release_profile_team}" == "${release_team_id}" ]] \
        || release_die "${release_profile_name} belongs to team ${release_profile_team}, expected ${release_team_id}"
    [[ "${release_profile_app_identifier}" == "${release_expected_app_identifier}" ]] \
        || release_die "${release_profile_name} has application-identifier ${release_profile_app_identifier}, expected ${release_expected_app_identifier}"
    [[ "${release_profile_group}" == "${release_app_group_id}" ]] \
        || release_die "${release_profile_name} has App Group ${release_profile_group}, expected ${release_app_group_id}"
    [[ "${release_profile_autofill}" == "true" ]] \
        || release_die "${release_profile_name} does not contain the AutoFill credential provider capability"
    [[ "${release_get_task_allow}" == "false" ]] \
        || release_die "${release_profile_name} is not an App Store distribution profile"

    if security cms -D -i "${release_profile_path}" 2>/dev/null \
        | plutil -extract ProvisionedDevices json -o - - >/dev/null 2>&1; then
        release_die "${release_profile_name} contains registered devices and is not an App Store profile"
    fi

    release_info "profile OK: ${release_profile_name}"
}

release_signing_check() {
    local release_required_xcode
    local release_actual_xcode
    local release_search_keychain
    local release_key_mode

    release_config_check
    release_required_xcode="$(tr -d '[:space:]' < "${release_repo_root}/.xcode-version")"
    release_actual_xcode="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
    if [[ "${release_actual_xcode}" != "${release_required_xcode}" ]]; then
        if [[ "${PBMEDIA_ALLOW_XCODE_MISMATCH:-0}" == "1" ]]; then
            release_warn "Xcode ${release_actual_xcode} differs from required ${release_required_xcode}; override accepted"
        else
            release_die "Xcode ${release_actual_xcode} differs from required ${release_required_xcode}"
        fi
    fi

    release_require_file "${release_api_key_path}"
    release_key_mode="$(stat -f '%Lp' "${release_api_key_path}")"
    [[ "${release_key_mode}" == "600" ]] \
        || release_die "App Store Connect key permissions are ${release_key_mode}; expected 600"

    release_require_file "${release_signing_keychain}"
    release_search_keychain="$(
        security list-keychains -d user \
            | tr -d '"' \
            | sed -e 's/^[[:space:]]*//' \
            | grep -Fx "${release_signing_keychain}" || true
    )"
    [[ "${release_search_keychain}" == "${release_signing_keychain}" ]] \
        || release_die "signing keychain is not in the user keychain search list: ${release_signing_keychain}"
    security find-identity -v -p codesigning "${release_signing_keychain}" \
        | grep -Fq '"Apple Distribution: PB Media LLC' \
        || release_die "Apple Distribution: PB Media LLC is not accessible in ${release_signing_keychain}; this script will not unlock it"

    release_validate_profile "${release_main_profile}" "${release_team_id}.${release_main_bundle_id}"
    release_validate_profile "${release_autofill_profile}" "${release_team_id}.${release_autofill_bundle_id}"
    release_info "local signing assets OK"
}

release_paths() {
    local release_marketing_version
    local release_build_number
    release_marketing_version="$(release_setting MARKETING_VERSION)"
    release_build_number="$(release_setting CURRENT_PROJECT_VERSION)"
    release_artifact_root="${PBMEDIA_RELEASE_ROOT:-${release_repo_root}/build/pbmedia-release}"
    release_archive_path="${release_artifact_root}/FRIDAY-Vault-${release_marketing_version}-${release_build_number}.xcarchive"
    release_export_path="${release_artifact_root}/FRIDAY-Vault-${release_marketing_version}-${release_build_number}-export"
    release_derived_data_path="${release_artifact_root}/DerivedData-${release_build_number}"
    release_archive_result_path="${release_artifact_root}/Archive-${release_build_number}.xcresult"
    release_export_result_path="${release_artifact_root}/Export-${release_build_number}.xcresult"
}

release_archive() {
    release_signing_check
    release_paths
    [[ ! -e "${release_archive_path}" ]] || release_die "archive path already exists: ${release_archive_path}"
    [[ ! -e "${release_archive_result_path}" ]] || release_die "archive result already exists: ${release_archive_result_path}"
    mkdir -p "${release_artifact_root}"

    release_info "regenerating ignored Xcode projects from project-bwk.yml and project-pm.yml"
    (
        cd "${release_repo_root}"
        mint run xcodegen --spec project-bwk.yml
        mint run xcodegen --spec project-pm.yml
    )

    release_info "archiving locally; Developer portal updates are disabled"
    xcrun xcodebuild archive \
        -workspace "${release_repo_root}/Bitwarden.xcworkspace" \
        -scheme Bitwarden \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "${release_archive_path}" \
        -derivedDataPath "${release_derived_data_path}" \
        -resultBundlePath "${release_archive_result_path}" \
        -hideShellScriptEnvironment \
        DEVELOPMENT_TEAM="${release_team_id}" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY='Apple Distribution' \
        PROVISIONING_PROFILE_SPECIFIER_MAIN_APP="${release_main_profile}" \
        PROVISIONING_PROFILE_SPECIFIER_AUTOFILL_EXTENSION="${release_autofill_profile}"

    release_info "archive created: ${release_archive_path}"
}

release_export() {
    local release_requested_archive="${1:-}"
    release_signing_check
    release_paths
    if [[ -n "${release_requested_archive}" ]]; then
        release_archive_path="${release_requested_archive}"
    fi
    [[ -d "${release_archive_path}" ]] || release_die "archive not found: ${release_archive_path}"
    [[ ! -e "${release_export_path}" ]] || release_die "export path already exists: ${release_export_path}"
    [[ ! -e "${release_export_result_path}" ]] || release_die "export result already exists: ${release_export_result_path}"

    release_info "exporting IPA locally; upload is disabled"
    xcrun xcodebuild -exportArchive \
        -archivePath "${release_archive_path}" \
        -exportPath "${release_export_path}" \
        -exportOptionsPlist "${release_export_options}" \
        -resultBundlePath "${release_export_result_path}"

    release_info "export created: ${release_export_path}"
}

release_cleanup_root=""

release_cleanup() {
    if [[ -z "${release_cleanup_root}" ]]; then
        return
    fi
    case "${release_cleanup_root}" in
        /tmp/friday-vault-release.*|/private/tmp/friday-vault-release.*|/var/folders/*/friday-vault-release.*|/private/var/folders/*/friday-vault-release.*)
            rm -rf -- "${release_cleanup_root}"
            ;;
        *)
            release_warn "refusing to remove unexpected temporary path: ${release_cleanup_root}"
            ;;
    esac
    release_cleanup_root=""
}

trap release_cleanup EXIT

release_decode_profile() {
    local release_profile_path="$1"
    local release_output_path="$2"
    security cms -D -i "${release_profile_path}" > "${release_output_path}" 2>/dev/null \
        || release_die "cannot decode embedded profile: ${release_profile_path}"
    plutil -lint "${release_output_path}" >/dev/null \
        || release_die "invalid embedded profile: ${release_profile_path}"
}

release_validate_embedded_profile() {
    local release_profile_plist="$1"
    local release_expected_app_identifier="$2"
    local release_profile_app_identifier
    local release_profile_team
    local release_profile_group
    local release_profile_autofill
    local release_profile_get_task_allow

    release_profile_team="$(release_plist_value "${release_profile_plist}" "TeamIdentifier:0")"
    release_profile_app_identifier="$(release_plist_value "${release_profile_plist}" "Entitlements:application-identifier")"
    release_profile_group="$(release_plist_value "${release_profile_plist}" "Entitlements:com.apple.security.application-groups:0")"
    release_profile_autofill="$(release_plist_value "${release_profile_plist}" "Entitlements:com.apple.developer.authentication-services.autofill-credential-provider")"
    release_profile_get_task_allow="$(release_plist_value "${release_profile_plist}" "Entitlements:get-task-allow")"

    [[ "${release_profile_team}" == "${release_team_id}" ]] \
        || release_die "embedded profile team is ${release_profile_team}, expected ${release_team_id}"
    [[ "${release_profile_app_identifier}" == "${release_expected_app_identifier}" ]] \
        || release_die "embedded profile application-identifier is ${release_profile_app_identifier}, expected ${release_expected_app_identifier}"
    [[ "${release_profile_group}" == "${release_app_group_id}" ]] \
        || release_die "embedded profile App Group is ${release_profile_group}, expected ${release_app_group_id}"
    [[ "${release_profile_autofill}" == "true" ]] \
        || release_die "embedded profile does not contain the AutoFill credential provider capability"
    [[ "${release_profile_get_task_allow}" == "false" ]] \
        || release_die "embedded profile has get-task-allow=${release_profile_get_task_allow}"
}

release_capture_entitlements() {
    local release_bundle_path="$1"
    local release_output_path="$2"
    codesign -d --entitlements :- "${release_bundle_path}" > "${release_output_path}" 2>/dev/null \
        || release_die "cannot read code-signing entitlements: ${release_bundle_path}"
    plutil -lint "${release_output_path}" >/dev/null \
        || release_die "invalid code-signing entitlements: ${release_bundle_path}"
}

release_validate_signed_entitlements() {
    local release_entitlements_path="$1"
    local release_expected_app_identifier="$2"
    local release_application_identifier
    local release_signed_group
    local release_signed_autofill
    local release_signed_get_task_allow

    release_application_identifier="$(release_plist_value "${release_entitlements_path}" "application-identifier")"
    release_signed_group="$(release_plist_value "${release_entitlements_path}" "com.apple.security.application-groups:0")"
    release_signed_autofill="$(release_plist_value "${release_entitlements_path}" "com.apple.developer.authentication-services.autofill-credential-provider")"
    release_signed_get_task_allow="$(release_plist_value "${release_entitlements_path}" "get-task-allow" || true)"

    [[ "${release_application_identifier}" == "${release_expected_app_identifier}" ]] \
        || release_die "signed application-identifier is ${release_application_identifier}, expected ${release_expected_app_identifier}"
    [[ "${release_signed_group}" == "${release_app_group_id}" ]] \
        || release_die "signed App Group is ${release_signed_group}, expected ${release_app_group_id}"
    [[ "${release_signed_autofill}" == "true" ]] \
        || release_die "signed entitlements do not contain the AutoFill credential provider capability"
    [[ -z "${release_signed_get_task_allow}" || "${release_signed_get_task_allow}" == "false" ]] \
        || release_die "signed entitlements have get-task-allow=${release_signed_get_task_allow}"
}

release_verify_ipa() {
    local release_ipa_path="${1:-}"
    local release_payload_path
    local release_app_path
    local release_app_count
    local release_autofill_path=""
    local release_autofill_count=0
    local release_candidate_extension
    local release_candidate_bundle_id
    local release_expected_version
    local release_expected_build
    local release_actual_bundle_id
    local release_actual_version
    local release_actual_build
    local release_main_profile_plist
    local release_autofill_profile_plist
    local release_main_entitlements
    local release_autofill_entitlements
    local release_temp_parent

    release_config_check
    [[ -n "${release_ipa_path}" ]] || release_die "verify-ipa requires an IPA path"
    release_require_file "${release_ipa_path}"
    release_temp_parent="${TMPDIR:-/tmp}"
    release_cleanup_root="$(mktemp -d "${release_temp_parent%/}/friday-vault-release.XXXXXX")"
    ditto -x -k "${release_ipa_path}" "${release_cleanup_root}"
    release_payload_path="${release_cleanup_root}/Payload"
    [[ -d "${release_payload_path}" ]] || release_die "IPA has no Payload directory"

    release_app_count="$(find "${release_payload_path}" -maxdepth 1 -type d -name '*.app' | wc -l | tr -d '[:space:]')"
    [[ "${release_app_count}" == "1" ]] || release_die "IPA contains ${release_app_count} top-level app bundles, expected 1"
    release_app_path="$(find "${release_payload_path}" -maxdepth 1 -type d -name '*.app' -print -quit)"

    release_actual_bundle_id="$(release_plist_value "${release_app_path}/Info.plist" "CFBundleIdentifier")"
    release_actual_version="$(release_plist_value "${release_app_path}/Info.plist" "CFBundleShortVersionString")"
    release_actual_build="$(release_plist_value "${release_app_path}/Info.plist" "CFBundleVersion")"
    release_expected_version="$(release_setting MARKETING_VERSION)"
    release_expected_build="$(release_setting CURRENT_PROJECT_VERSION)"
    [[ "${release_actual_bundle_id}" == "${release_main_bundle_id}" ]] \
        || release_die "IPA main bundle ID is ${release_actual_bundle_id}, expected ${release_main_bundle_id}"
    [[ "${release_actual_version}" == "${release_expected_version}" ]] \
        || release_die "IPA version is ${release_actual_version}, expected ${release_expected_version}"
    [[ "${release_actual_build}" == "${release_expected_build}" ]] \
        || release_die "IPA build is ${release_actual_build}, expected ${release_expected_build}"

    if [[ -d "${release_app_path}/PlugIns" ]]; then
        while IFS= read -r -d '' release_candidate_extension; do
            release_candidate_bundle_id="$(release_plist_value "${release_candidate_extension}/Info.plist" "CFBundleIdentifier")"
            if [[ "${release_candidate_bundle_id}" == "${release_autofill_bundle_id}" ]]; then
                release_autofill_path="${release_candidate_extension}"
                release_autofill_count=$((release_autofill_count + 1))
            fi
        done < <(find "${release_app_path}/PlugIns" -maxdepth 1 -type d -name '*.appex' -print0)
    fi
    [[ "${release_autofill_count}" == "1" ]] \
        || release_die "IPA contains ${release_autofill_count} matching AutoFill extensions, expected 1"

    codesign --verify --strict "${release_autofill_path}"
    codesign --verify --deep --strict "${release_app_path}"

    release_main_profile_plist="${release_cleanup_root}/main-profile.plist"
    release_autofill_profile_plist="${release_cleanup_root}/autofill-profile.plist"
    release_main_entitlements="${release_cleanup_root}/main-entitlements.plist"
    release_autofill_entitlements="${release_cleanup_root}/autofill-entitlements.plist"
    release_decode_profile "${release_app_path}/embedded.mobileprovision" "${release_main_profile_plist}"
    release_decode_profile "${release_autofill_path}/embedded.mobileprovision" "${release_autofill_profile_plist}"
    release_validate_embedded_profile "${release_main_profile_plist}" "${release_team_id}.${release_main_bundle_id}"
    release_validate_embedded_profile "${release_autofill_profile_plist}" "${release_team_id}.${release_autofill_bundle_id}"

    release_capture_entitlements "${release_app_path}" "${release_main_entitlements}"
    release_capture_entitlements "${release_autofill_path}" "${release_autofill_entitlements}"
    release_validate_signed_entitlements "${release_main_entitlements}" "${release_team_id}.${release_main_bundle_id}"
    release_validate_signed_entitlements "${release_autofill_entitlements}" "${release_team_id}.${release_autofill_bundle_id}"

    release_info "IPA verified (${release_actual_bundle_id} ${release_actual_version} build ${release_actual_build})"
    release_cleanup
}

release_upload() {
    local release_ipa_path="${1:-}"
    local release_build_number
    local release_expected_guard

    [[ -n "${release_ipa_path}" ]] || release_die "upload requires an IPA path"
    release_verify_ipa "${release_ipa_path}"
    release_require_file "${release_api_key_path}"
    release_build_number="$(release_setting CURRENT_PROJECT_VERSION)"
    release_expected_guard="UPLOAD-${release_build_number}"
    [[ "${PBMEDIA_CONFIRM_UPLOAD:-}" == "${release_expected_guard}" ]] \
        || release_die "refusing upload; set PBMEDIA_CONFIRM_UPLOAD=${release_expected_guard}"

    release_warn "uploading ${release_ipa_path} to App Store Connect"
    xcrun altool --upload-app \
        -f "${release_ipa_path}" \
        -t ios \
        --apiKey "${release_key_id}" \
        --apiIssuer "${release_issuer_id}"
}

release_command="${1:-}"
case "${release_command}" in
    config-check)
        release_config_check
        ;;
    signing-check)
        release_signing_check
        ;;
    archive)
        release_archive
        ;;
    export)
        release_export "${2:-}"
        ;;
    verify-ipa)
        release_verify_ipa "${2:-}"
        ;;
    upload)
        release_upload "${2:-}"
        ;;
    -h|--help|help)
        release_usage
        ;;
    *)
        release_usage >&2
        exit 64
        ;;
esac
