@preconcurrency import AppAuth
import Foundation
import UIKit

@MainActor
final class AppAuthGmailAuthenticationService: AccountGateway, GmailAccessTokenProviding {
    private struct GoogleProfileDTO: Decodable {
        let sub: String
        let email: String
        let name: String?
    }

    private let configuration: GoogleOAuthConfiguration?
    private let credentials: any CredentialDataStoring
    private let metadata: any AccountMetadataStoring
    private let transport: any HTTPTransport
    private var currentAuthorizationFlow: (any OIDExternalUserAgentSession)?

    init(
        configuration: GoogleOAuthConfiguration?,
        credentials: any CredentialDataStoring,
        metadata: any AccountMetadataStoring,
        transport: any HTTPTransport
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.metadata = metadata
        self.transport = transport
    }

    func connectedAccounts() async throws -> [MailAccount] {
        let saved = try await metadata.accounts()
        var result: [MailAccount] = []
        for account in saved {
            let state: OIDAuthState?
            do {
                state = try await loadState(for: account.id)
            } catch AccessTokenError.authenticationRequired {
                state = nil
            }
            let connectionState: MailAccount.ConnectionState = state?.isAuthorized == true
                ? .connected
                : .authenticationRequired
            let updated = account.withConnectionState(connectionState)
            if updated != account {
                try await metadata.save(updated)
            }
            result.append(updated)
        }
        return result.sorted { $0.emailAddress.localizedCaseInsensitiveCompare($1.emailAddress) == .orderedAscending }
    }

    func connect(provider: MailProvider) async throws -> MailAccount {
        guard provider == .gmail else { throw AccountManagementError.configurationMissing }
        let state = try await authorize(loginHint: nil)
        return try await persistNewAccount(from: state)
    }

    func reconnect(_ account: MailAccount) async throws -> MailAccount {
        let state = try await authorize(loginHint: account.emailAddress)
        let profile = try await profile(using: state)
        let expectedID = MailAccount.ID(rawValue: "gmail:\(profile.sub)")
        guard expectedID == account.id else {
            throw AccountManagementError.authenticationFailed
        }
        let connected = MailAccount(
            id: account.id,
            provider: .gmail,
            emailAddress: profile.email,
            displayName: profile.name,
            connectionState: .connected
        )
        try await save(state, for: connected.id)
        try await metadata.save(connected)
        return connected
    }

    func disconnect(_ account: MailAccount) async throws {
        if let state = try? await loadState(for: account.id),
           let token = state.lastTokenResponse?.refreshToken
                ?? state.lastTokenResponse?.accessToken {
            await revoke(token)
        }
        try await credentials.removeData(for: account.id)
        try await metadata.remove(account.id)
    }

    func accessToken(for accountID: MailAccount.ID, forceRefresh: Bool) async throws -> String {
        guard let state = try await loadState(for: accountID) else {
            throw AccessTokenError.authenticationRequired
        }
        if forceRefresh {
            state.setNeedsTokenRefresh()
        }

        let token: String = try await withCheckedThrowingContinuation { continuation in
            state.performAction { accessToken, _, error in
                if error != nil {
                    continuation.resume(throwing: AccessTokenError.authenticationRequired)
                } else if let accessToken, !accessToken.isEmpty {
                    continuation.resume(returning: accessToken)
                } else {
                    continuation.resume(throwing: AccessTokenError.unavailable)
                }
            }
        }
        try await save(state, for: accountID)
        return token
    }

    private func authorize(loginHint: String?) async throws -> OIDAuthState {
        guard let configuration else { throw AccountManagementError.configurationMissing }
        guard let presentingViewController = Self.presentingViewController() else {
            throw AccountManagementError.authenticationFailed
        }
        let serviceConfiguration = OIDServiceConfiguration(
            authorizationEndpoint: configuration.authorizationEndpoint,
            tokenEndpoint: configuration.tokenEndpoint
        )
        var parameters = [
            "access_type": "offline",
            "include_granted_scopes": "true",
            "prompt": "consent select_account",
        ]
        if let loginHint {
            parameters["login_hint"] = loginHint
        }
        let request = OIDAuthorizationRequest(
            configuration: serviceConfiguration,
            clientId: configuration.clientID,
            clientSecret: nil,
            scopes: [
                OIDScopeOpenID,
                "email",
                "https://www.googleapis.com/auth/gmail.readonly",
            ],
            redirectURL: configuration.redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: parameters
        )

        return try await withCheckedThrowingContinuation { continuation in
            currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: presentingViewController
            ) { [weak self] state, error in
                self?.currentAuthorizationFlow = nil
                if let state {
                    continuation.resume(returning: state)
                } else if (error as NSError?)?.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: AccountManagementError.authenticationFailed)
                }
            }
        }
    }

    private func persistNewAccount(from state: OIDAuthState) async throws -> MailAccount {
        let profile = try await profile(using: state)
        let account = MailAccount(
            id: .init(rawValue: "gmail:\(profile.sub)"),
            provider: .gmail,
            emailAddress: profile.email,
            displayName: profile.name,
            connectionState: .connected
        )
        try await save(state, for: account.id)
        do {
            try await metadata.save(account)
        } catch {
            try? await credentials.removeData(for: account.id)
            throw AccountManagementError.storageUnavailable
        }
        return account
    }

    private func profile(using state: OIDAuthState) async throws -> GoogleProfileDTO {
        let token: String = try await withCheckedThrowingContinuation { continuation in
            state.performAction { accessToken, _, error in
                if error != nil {
                    continuation.resume(throwing: AccountManagementError.authenticationFailed)
                } else if let accessToken {
                    continuation.resume(returning: accessToken)
                } else {
                    continuation.resume(throwing: AccountManagementError.authenticationFailed)
                }
            }
        }
        guard let configuration else { throw AccountManagementError.configurationMissing }
        var request = URLRequest(url: configuration.userInfoEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AccountManagementError.authenticationFailed
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AccountManagementError.authenticationFailed
        }
        do {
            return try JSONDecoder().decode(GoogleProfileDTO.self, from: response.data)
        } catch {
            throw AccountManagementError.authenticationFailed
        }
    }

    private func save(_ state: OIDAuthState, for accountID: MailAccount.ID) async throws {
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: state,
                requiringSecureCoding: true
            )
            try await credentials.save(data, for: accountID)
        } catch {
            throw AccessTokenError.unavailable
        }
    }

    private func loadState(for accountID: MailAccount.ID) async throws -> OIDAuthState? {
        guard let data = try await credentials.data(for: accountID) else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
        } catch {
            throw AccessTokenError.authenticationRequired
        }
    }

    private func revoke(_ token: String) async {
        guard let configuration else { return }
        var components = URLComponents(url: configuration.revocationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try? await transport.send(request)
    }

    private static func presentingViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        return topViewController(from: root)
    }

    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tabs = root as? UITabBarController {
            return topViewController(from: tabs.selectedViewController)
        }
        return root
    }
}

private extension MailAccount {
    func withConnectionState(_ state: ConnectionState) -> MailAccount {
        MailAccount(
            id: id,
            provider: provider,
            emailAddress: emailAddress,
            displayName: displayName,
            connectionState: state
        )
    }
}
