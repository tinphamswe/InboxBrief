import Foundation

struct GoogleOAuthConfiguration: Sendable {
    let clientID: String
    let redirectURI: URL
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let userInfoEndpoint: URL
    let revocationEndpoint: URL

    init?(
        clientID: String,
        redirectScheme: String,
        authorizationEndpoint: String = "https://accounts.google.com/o/oauth2/v2/auth",
        tokenEndpoint: String = "https://oauth2.googleapis.com/token",
        userInfoEndpoint: String = "https://openidconnect.googleapis.com/v1/userinfo",
        revocationEndpoint: String = "https://oauth2.googleapis.com/revoke"
    ) {
        guard
            !clientID.isEmpty,
            !redirectScheme.isEmpty,
            !clientID.contains("REPLACE_ME"),
            !redirectScheme.contains("REPLACE_ME"),
            let redirectURI = URL(string: "\(redirectScheme):/oauthredirect"),
            let authorizationURL = URL(string: authorizationEndpoint),
            let tokenURL = URL(string: tokenEndpoint),
            let userInfoURL = URL(string: userInfoEndpoint),
            let revocationURL = URL(string: revocationEndpoint)
        else {
            return nil
        }
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.authorizationEndpoint = authorizationURL
        self.tokenEndpoint = tokenURL
        self.userInfoEndpoint = userInfoURL
        self.revocationEndpoint = revocationURL
    }
}
