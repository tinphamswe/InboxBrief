import Foundation
import Testing
@testable import InboxBrief

@Suite("Gmail infrastructure")
struct GmailInfrastructureTests {
    @Test("maps Gmail MIME data into a provider-independent message")
    func mapsMessage() throws {
        let account = makeAccount()
        let encodedBody = Data("Please reply by Friday.".utf8).base64URLEncodedString()
        let dto = GmailMessageDTO(
            id: "gmail-id",
            threadId: "thread-id",
            snippet: "fallback",
            internalDate: "1000000",
            payload: GmailMessagePartDTO(
                mimeType: "multipart/alternative",
                filename: "",
                headers: [
                    GmailHeaderDTO(name: "From", value: "Taylor <taylor@example.com>"),
                    GmailHeaderDTO(name: "Subject", value: "Project deadline"),
                    GmailHeaderDTO(name: "Message-ID", value: "<unique@example.com>"),
                ],
                body: nil,
                parts: [
                    GmailMessagePartDTO(
                        mimeType: "text/plain",
                        filename: "",
                        headers: nil,
                        body: GmailMessagePartBodyDTO(data: encodedBody, attachmentId: nil),
                        parts: nil
                    ),
                ]
            )
        )

        let message = try GmailMessageMapper().map(dto, account: account)

        #expect(message.id.rawValue == "gmail:account:gmail-id")
        #expect(message.sender.name == "Taylor")
        #expect(message.sender.address == "taylor@example.com")
        #expect(message.subject == "Project deadline")
        #expect(message.analysisText == "Please reply by Friday.")
        #expect(message.originalTarget?.searchQuery == "rfc822msgid:unique@example.com")
    }

    @Test("sanitizes HTML when no plaintext part exists")
    func mapsHTMLFallback() throws {
        let html = "<style>hidden</style><p>Hello &amp; welcome</p><script>bad()</script>"
        let dto = GmailMessageDTO(
            id: "id",
            threadId: "thread",
            snippet: nil,
            internalDate: "1000",
            payload: GmailMessagePartDTO(
                mimeType: "text/html",
                filename: "",
                headers: [],
                body: GmailMessagePartBodyDTO(
                    data: Data(html.utf8).base64URLEncodedString(),
                    attachmentId: nil
                ),
                parts: nil
            )
        )

        let message = try GmailMessageMapper().map(dto, account: makeAccount())

        #expect(message.analysisText.contains("Hello & welcome"))
        #expect(!message.analysisText.contains("bad()"))
        #expect(!message.analysisText.contains("hidden"))
    }

    @Test("rejects a message without stable identity or receipt date")
    func malformedMessage() {
        let dto = GmailMessageDTO(id: nil, threadId: nil, snippet: nil, internalDate: nil, payload: nil)
        #expect(throws: MailFetchError.invalidResponse) {
            try GmailMessageMapper().map(dto, account: makeAccount())
        }
    }

    @Test("follows pagination and maps message details")
    func pagination() async throws {
        let transport = GmailRoutingTransport { request in
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let pageToken = components.queryItems?.first(where: { $0.name == "pageToken" })?.value
            if url.path.hasSuffix("/messages") {
                return HTTPResponse(
                    data: Data((pageToken == nil
                        ? #"{"messages":[{"id":"one"}],"nextPageToken":"next"}"#
                        : #"{"messages":[{"id":"two"}]}"#).utf8),
                    statusCode: 200,
                    headers: [:]
                )
            }
            let id = url.lastPathComponent
            return HTTPResponse(
                data: Self.detailJSON(id: id, milliseconds: id == "one" ? 2_000_000 : 3_000_000),
                statusCode: 200,
                headers: [:]
            )
        }
        let baseURL = try #require(URL(string: "https://example.test/gmail/v1"))
        let fetcher = GmailRecentEmailFetcher(
            transport: transport,
            tokens: GmailTokenProvider(),
            baseURL: baseURL
        )

        let messages = try await fetcher.fetchRecentEmails(
            for: makeAccount(),
            since: Date(timeIntervalSince1970: 1_000)
        )

        #expect(messages.map(\.subject) == ["two", "one"])
        let requests = await transport.requests
        #expect(requests.filter { $0.url?.path.hasSuffix("/messages") == true }.count == 2)
    }

    @Test("retries once with a refreshed token after HTTP 401")
    func authenticationRetry() async throws {
        let transport = Counting401Transport()
        let tokenProvider = RecordingTokenProvider()
        let baseURL = try #require(URL(string: "https://example.test/gmail/v1"))
        let fetcher = GmailRecentEmailFetcher(
            transport: transport,
            tokens: tokenProvider,
            baseURL: baseURL
        )

        _ = try await fetcher.fetchRecentEmails(
            for: makeAccount(),
            since: Date(timeIntervalSince1970: 1_000)
        )

        #expect(await tokenProvider.forceRefreshValues == [false, true])
    }

    private static func detailJSON(id: String, milliseconds: Int) -> Data {
        Data("""
        {"id":"\(id)","threadId":"thread","internalDate":"\(milliseconds)","snippet":"Body","payload":{"headers":[{"name":"From","value":"Sender <sender@example.com>"},{"name":"Subject","value":"\(id)"}]}}
        """.utf8)
    }

    private func makeAccount() -> MailAccount {
        MailAccount(
            id: .init(rawValue: "account"),
            provider: .gmail,
            emailAddress: "person@example.com",
            displayName: nil,
            connectionState: .connected
        )
    }
}

private struct GmailRoutingTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> HTTPResponse
    private let recorder = RequestRecorder()

    init(handler: @escaping @Sendable (URLRequest) throws -> HTTPResponse) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        get async { await recorder.values }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        await recorder.append(request)
        return try handler(request)
    }
}

private actor RequestRecorder {
    private(set) var values: [URLRequest] = []
    func append(_ request: URLRequest) { values.append(request) }
}

@MainActor
private struct GmailTokenProvider: GmailAccessTokenProviding {
    func accessToken(for accountID: MailAccount.ID, forceRefresh: Bool) async throws -> String {
        "token"
    }
}

private actor Counting401Transport: HTTPTransport {
    private var count = 0

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        count += 1
        if count == 1 {
            return HTTPResponse(data: Data(), statusCode: 401, headers: [:])
        }
        return HTTPResponse(data: Data(#"{"messages":[]}"#.utf8), statusCode: 200, headers: [:])
    }
}

@MainActor
private final class RecordingTokenProvider: GmailAccessTokenProviding {
    private(set) var forceRefreshValues: [Bool] = []

    func accessToken(for accountID: MailAccount.ID, forceRefresh: Bool) async throws -> String {
        forceRefreshValues.append(forceRefresh)
        return forceRefresh ? "new" : "old"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
