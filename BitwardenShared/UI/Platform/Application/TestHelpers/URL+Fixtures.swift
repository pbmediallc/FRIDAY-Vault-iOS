import Foundation

#if DEBUG
extension URL {
    static let bitwardenAccountSecurity = URL(string: "fridayvault://settings/account_security")!
    static let bitwardenAuthenticatorNewItem = URL(string: "fridayvault://authenticator/newItem")!
    static let bitwardenInvalidPath = URL(string: "fridayvault://unsupported/urll")!
    static let bitwardenSchemeOnly = URL(string: "fridayvault://")!
    static let bitwardenSSOCookieVendor = URL(string: "bitwarden://sso-cookie-vendor?auth=token123&session=abc")!
    static let bitwardenSSOCookieVendorNoCookies = URL(string: "bitwarden://sso-cookie-vendor")!
    static let bitwardenSSOCookieVendorDParam = URL(string: "bitwarden://sso-cookie-vendor?d=ignored&auth=myToken")!
}
#endif
