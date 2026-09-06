import Foundation

struct GmailMessageMapper: Sendable {
    private let maximumNormalizedCharacters: Int

    init(maximumNormalizedCharacters: Int = 12_000) {
        self.maximumNormalizedCharacters = maximumNormalizedCharacters
    }

    func map(_ dto: GmailMessageDTO, account: MailAccount) throws -> EmailMessage {
        guard
            let providerID = dto.id,
            !providerID.isEmpty,
            let milliseconds = dto.internalDate.flatMap(Double.init)
        else {
            throw MailFetchError.invalidResponse
        }

        let headers = headerDictionary(from: dto.payload?.headers ?? [])
        let subject = nonempty(headers["subject"]) ?? "(No subject)"
        let sender = parseSender(headers["from"])
        let body = extractBody(from: dto.payload)
        let fallback = dto.snippet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = normalize(body.isEmpty ? fallback : body)
        let searchQuery = messageSearchQuery(from: headers["message-id"])

        return EmailMessage(
            id: .init(rawValue: "gmail:\(account.id.rawValue):\(providerID)"),
            accountID: account.id,
            accountAddress: account.emailAddress,
            sender: sender,
            subject: subject,
            receivedAt: Date(timeIntervalSince1970: milliseconds / 1_000),
            analysisText: String(normalized.prefix(maximumNormalizedCharacters)),
            originalTarget: originalTarget(for: account, searchQuery: searchQuery)
        )
    }

    private func headerDictionary(from headers: [GmailHeaderDTO]) -> [String: String] {
        headers.reduce(into: [:]) { result, header in
            guard let name = header.name?.lowercased(), let value = header.value else { return }
            result[name] = value
        }
    }

    private func parseSender(_ rawValue: String?) -> EmailSender {
        guard let rawValue = nonempty(rawValue) else {
            return EmailSender(name: nil, address: "Unknown sender")
        }
        guard
            let opening = rawValue.lastIndex(of: "<"),
            let closing = rawValue.lastIndex(of: ">"),
            opening < closing
        else {
            return EmailSender(name: nil, address: rawValue)
        }

        let name = rawValue[..<opening]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let address = rawValue[rawValue.index(after: opening)..<closing]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return EmailSender(name: nonempty(name), address: address)
    }

    private func extractBody(from root: GmailMessagePartDTO?) -> String {
        guard let root else { return "" }
        var plain: [String] = []
        var html: [String] = []
        collectText(in: root, plain: &plain, html: &html)

        if !plain.isEmpty {
            return plain.joined(separator: "\n")
        }
        return html.map(HTMLTextSanitizer.sanitize).joined(separator: "\n")
    }

    private func collectText(
        in part: GmailMessagePartDTO,
        plain: inout [String],
        html: inout [String]
    ) {
        let filename = part.filename?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if filename.isEmpty, let encoded = part.body?.data, let text = decodeBase64URL(encoded) {
            switch part.mimeType?.lowercased() {
            case "text/plain": plain.append(text)
            case "text/html": html.append(text)
            default: break
            }
        }

        for child in part.parts ?? [] {
            collectText(in: child, plain: &plain, html: &html)
        }
    }

    private func decodeBase64URL(_ value: String) -> String? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func messageSearchQuery(from messageID: String?) -> String? {
        guard var value = nonempty(messageID) else { return nil }
        if value.hasPrefix("<") { value.removeFirst() }
        if value.hasSuffix(">") { value.removeLast() }
        guard !value.isEmpty else { return nil }
        return "rfc822msgid:\(value)"
    }

    private func originalTarget(
        for account: MailAccount,
        searchQuery: String?
    ) -> OriginalMessageTarget? {
        var components = URLComponents(string: "https://mail.google.com/mail/")
        components?.queryItems = [URLQueryItem(name: "authuser", value: account.emailAddress)]
        guard let url = components?.url else { return nil }
        return OriginalMessageTarget(webURL: url, searchQuery: searchQuery)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum HTMLTextSanitizer {
    static func sanitize(_ html: String) -> String {
        var result = html
        result = replacing(#"(?is)<(script|style)[^>]*>.*?</\1>"#, in: result, with: " ")
        result = replacing(#"(?i)<br\s*/?>|</p>|</div>|</li>|</tr>"#, in: result, with: "\n")
        result = replacing(#"<[^>]+>"#, in: result, with: " ")

        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        ]
        for (entity, value) in entities {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}
