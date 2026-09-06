import Foundation

struct GmailMessageListDTO: Decodable, Sendable {
    let messages: [GmailMessageReferenceDTO]?
    let nextPageToken: String?
}

struct GmailMessageReferenceDTO: Decodable, Sendable {
    let id: String?
    let threadId: String?
}

struct GmailMessageDTO: Decodable, Sendable {
    let id: String?
    let threadId: String?
    let snippet: String?
    let internalDate: String?
    let payload: GmailMessagePartDTO?
}

struct GmailMessagePartDTO: Decodable, Sendable {
    let mimeType: String?
    let filename: String?
    let headers: [GmailHeaderDTO]?
    let body: GmailMessagePartBodyDTO?
    let parts: [GmailMessagePartDTO]?
}

struct GmailHeaderDTO: Decodable, Sendable {
    let name: String?
    let value: String?
}

struct GmailMessagePartBodyDTO: Decodable, Sendable {
    let data: String?
    let attachmentId: String?
}
