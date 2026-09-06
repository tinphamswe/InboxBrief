import Foundation

struct HTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]
}

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPTransportError.invalidResponse
        }
        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String, let value = pair.value as? String else { return }
            result[key] = value
        }
        return HTTPResponse(data: data, statusCode: httpResponse.statusCode, headers: headers)
    }
}

enum HTTPTransportError: Error, Sendable {
    case invalidResponse
}
