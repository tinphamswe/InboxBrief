import Foundation

struct GmailRecentEmailFetcher: RecentEmailFetching {
    private let transport: any HTTPTransport
    private let tokens: any GmailAccessTokenProviding
    private let mapper: GmailMessageMapper
    private let baseURL: URL
    private let detailBatchSize: Int
    private let decoder: JSONDecoder

    init(
        transport: any HTTPTransport,
        tokens: any GmailAccessTokenProviding,
        mapper: GmailMessageMapper = GmailMessageMapper(),
        baseURL: URL,
        detailBatchSize: Int = 10
    ) {
        self.transport = transport
        self.tokens = tokens
        self.mapper = mapper
        self.baseURL = baseURL
        self.detailBatchSize = max(1, detailBatchSize)
        decoder = JSONDecoder()
    }

    func fetchRecentEmails(for account: MailAccount, since cutoff: Date) async throws -> [EmailMessage] {
        guard account.provider == .gmail else {
            throw MailFetchError.providerUnavailable
        }

        let references = try await fetchAllReferences(for: account, since: cutoff)
        let messages = try await fetchDetails(references, for: account)
        return messages
            .filter { $0.receivedAt >= cutoff }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    private func fetchAllReferences(
        for account: MailAccount,
        since cutoff: Date
    ) async throws -> [GmailMessageReferenceDTO] {
        var references: [GmailMessageReferenceDTO] = []
        var pageToken: String?
        var seenPageTokens: Set<String> = []

        repeat {
            try Task.checkCancellation()
            let request = try listRequest(since: cutoff, pageToken: pageToken)
            let data = try await authorizedData(for: request, accountID: account.id)
            let page: GmailMessageListDTO
            do {
                page = try decoder.decode(GmailMessageListDTO.self, from: data)
            } catch {
                throw MailFetchError.invalidResponse
            }
            references.append(contentsOf: page.messages ?? [])

            if let next = page.nextPageToken {
                guard !next.isEmpty, seenPageTokens.insert(next).inserted else {
                    throw MailFetchError.invalidResponse
                }
            }
            pageToken = page.nextPageToken
        } while pageToken != nil

        guard references.allSatisfy({ !($0.id?.isEmpty ?? true) }) else {
            throw MailFetchError.invalidResponse
        }
        return references
    }

    private func fetchDetails(
        _ references: [GmailMessageReferenceDTO],
        for account: MailAccount
    ) async throws -> [EmailMessage] {
        var mappedMessages: [EmailMessage] = []

        for start in stride(from: 0, to: references.count, by: detailBatchSize) {
            try Task.checkCancellation()
            let end = min(start + detailBatchSize, references.count)
            let batch = references[start..<end]
            let mapped = try await withThrowingTaskGroup(of: EmailMessage.self) { group in
                for reference in batch {
                    guard let id = reference.id else { throw MailFetchError.invalidResponse }
                    group.addTask {
                        let request = try detailRequest(messageID: id)
                        let data = try await authorizedData(for: request, accountID: account.id)
                        let dto: GmailMessageDTO
                        do {
                            dto = try decoder.decode(GmailMessageDTO.self, from: data)
                        } catch {
                            throw MailFetchError.invalidResponse
                        }
                        return try mapper.map(dto, account: account)
                    }
                }

                var result: [EmailMessage] = []
                for try await message in group {
                    result.append(message)
                }
                return result
            }
            mappedMessages.append(contentsOf: mapped)
        }
        return mappedMessages
    }

    private func listRequest(since cutoff: Date, pageToken: String?) throws -> URLRequest {
        let url = baseURL.appending(path: "users/me/messages")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw MailFetchError.invalidResponse
        }
        var queryItems = [
            URLQueryItem(name: "labelIds", value: "INBOX"),
            URLQueryItem(name: "maxResults", value: "500"),
            URLQueryItem(name: "q", value: "after:\(Int(cutoff.timeIntervalSince1970))"),
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = queryItems
        guard let requestURL = components.url else { throw MailFetchError.invalidResponse }
        return URLRequest(url: requestURL)
    }

    private func detailRequest(messageID: String) throws -> URLRequest {
        let url = baseURL
            .appending(path: "users/me/messages")
            .appending(path: messageID)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw MailFetchError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        guard let requestURL = components.url else { throw MailFetchError.invalidResponse }
        return URLRequest(url: requestURL)
    }

    private func authorizedData(
        for request: URLRequest,
        accountID: MailAccount.ID
    ) async throws -> Data {
        var firstRequest = request
        firstRequest.setValue(
            "Bearer \(try await accessToken(for: accountID, forceRefresh: false))",
            forHTTPHeaderField: "Authorization"
        )
        let firstResponse = try await send(firstRequest)
        if firstResponse.statusCode == 401 {
            var retry = request
            retry.setValue(
                "Bearer \(try await accessToken(for: accountID, forceRefresh: true))",
                forHTTPHeaderField: "Authorization"
            )
            return try validate(try await send(retry))
        }
        return try validate(firstResponse)
    }

    private func accessToken(for accountID: MailAccount.ID, forceRefresh: Bool) async throws -> String {
        do {
            return try await tokens.accessToken(for: accountID, forceRefresh: forceRefresh)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AccessTokenError where error == .authenticationRequired {
            throw MailFetchError.authenticationExpired
        } catch {
            throw MailFetchError.providerUnavailable
        }
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw MailFetchError.offline
        } catch let error as URLError where error.code == .networkConnectionLost {
            throw MailFetchError.offline
        } catch {
            throw MailFetchError.providerUnavailable
        }
    }

    private func validate(_ response: HTTPResponse) throws -> Data {
        switch response.statusCode {
        case 200..<300:
            return response.data
        case 401, 403:
            throw MailFetchError.authenticationExpired
        case 500..<600:
            throw MailFetchError.providerUnavailable
        default:
            throw MailFetchError.invalidResponse
        }
    }
}
