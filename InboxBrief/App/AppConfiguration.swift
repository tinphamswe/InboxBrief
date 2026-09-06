import Foundation

struct AppConfiguration: Sendable {
    enum AIConnection: Sendable {
        case openAI(endpoint: URL, key: String, model: String)
        case gemini(endpoint: URL, key: String, model: String)
        case fitAI(endpoint: URL, key: String, model: String, maximumConcurrentBatches: Int)
        case proxy(endpoint: URL)
        case unavailable
    }

    let googleOAuth: GoogleOAuthConfiguration?
    let aiConnection: AIConnection

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppConfiguration {
        let clientID = bundle.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? ""
        let redirectScheme = bundle.object(forInfoDictionaryKey: "GoogleRedirectScheme") as? String
            ?? environment["GOOGLE_REDIRECT_SCHEME"]
            ?? ""
        let googleOAuth = GoogleOAuthConfiguration(
            clientID: clientID,
            redirectScheme: redirectScheme
        )

        let aiConnection: AIConnection
#if DEBUG
        aiConnection = debugAIConnection(bundle: bundle, environment: environment)
#else
        if let proxy = proxyURL(bundle: bundle) {
            aiConnection = .proxy(endpoint: proxy)
        } else {
            aiConnection = .unavailable
        }
#endif
        return AppConfiguration(googleOAuth: googleOAuth, aiConnection: aiConnection)
    }

    private static func proxyURL(bundle: Bundle) -> URL? {
        guard let value = bundle.object(forInfoDictionaryKey: "AIProxyURL") as? String,
              !value.isEmpty,
              let url = URL(string: value),
              url.scheme == "https" else {
            return nil
        }
        return url
    }

#if DEBUG
    private static func debugAIConnection(
        bundle: Bundle,
        environment: [String: String]
    ) -> AIConnection {
        switch environment["INBOXBRIEF_AI_PROVIDER"]?.lowercased() {
        case "fitai":
            return fitAIConnection(environment: environment) ?? .unavailable
        case "gemini":
            return geminiConnection(environment: environment) ?? .unavailable
        case "openai":
            return openAIConnection(environment: environment) ?? .unavailable
        case "proxy":
            return proxyURL(bundle: bundle).map(AIConnection.proxy) ?? .unavailable
        default:
            return fitAIConnection(environment: environment)
                ?? geminiConnection(environment: environment)
                ?? openAIConnection(environment: environment)
                ?? proxyURL(bundle: bundle).map(AIConnection.proxy)
                ?? .unavailable
        }
    }

    private static func fitAIConnection(environment: [String: String]) -> AIConnection? {
        guard let key = nonemptyValue("INBOXBRIEF_FITAI_API_KEY", environment: environment),
              let baseURL = URL(
                string: nonemptyValue("INBOXBRIEF_FITAI_BASE_URL", environment: environment)
                    ?? "https://api-fit.hcmus.edu.vn/v1"
              ),
              baseURL.scheme == "https"
        else {
            return nil
        }
        return .fitAI(
            endpoint: baseURL.appending(path: "chat/completions"),
            key: key,
            model: nonemptyValue("INBOXBRIEF_FITAI_MODEL", environment: environment)
                ?? "Qwen-27B",
            maximumConcurrentBatches: fitAIMaximumConcurrentBatches(environment: environment)
        )
    }

    private static func fitAIMaximumConcurrentBatches(environment: [String: String]) -> Int {
        let configured = nonemptyValue(
            "INBOXBRIEF_FITAI_MAX_CONCURRENT_BATCHES",
            environment: environment
        ).flatMap(Int.init) ?? 8
        return min(max(configured, 1), 8)
    }

    private static func geminiConnection(environment: [String: String]) -> AIConnection? {
        guard let key = nonemptyValue("INBOXBRIEF_GEMINI_API_KEY", environment: environment),
              let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")
        else {
            return nil
        }
        return .gemini(
            endpoint: endpoint,
            key: key,
            model: nonemptyValue("INBOXBRIEF_GEMINI_MODEL", environment: environment)
                ?? "gemini-3.7-flash"
        )
    }

    private static func openAIConnection(environment: [String: String]) -> AIConnection? {
        guard let key = nonemptyValue("INBOXBRIEF_OPENAI_API_KEY", environment: environment),
              let endpoint = URL(string: "https://api.openai.com/v1/responses")
        else {
            return nil
        }
        return .openAI(
            endpoint: endpoint,
            key: key,
            model: nonemptyValue("INBOXBRIEF_OPENAI_MODEL", environment: environment)
                ?? "gpt-5-mini"
        )
    }

    private static func nonemptyValue(
        _ key: String,
        environment: [String: String]
    ) -> String? {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
#endif
}
