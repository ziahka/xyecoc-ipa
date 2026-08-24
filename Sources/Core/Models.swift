//
//  Models.swift
//  XyecocMail
//
//  Codable port of the Android `data/model/Models.kt` layer.
//  All backend I/O flows through the single RPC envelope `RequestPayload`
//  and the polymorphic `ApiResponse`. Decoding is deliberately lenient
//  (missing keys default, ints/strings coerced to Bool/Int64) because the
//  Gson-based backend is loosely typed and omits fields per action.
//

import Foundation

enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i):    try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b):   try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a):  try c.encode(a)
        case .null:          try c.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var intValue: Int64? {
        switch self {
        case .int(let i):    return i
        case .double(let d): return Int64(d)
        case .string(let s): return Int64(s)
        default:             return nil
        }
    }

    subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    func decoded<T: Decodable>(_ type: T.Type = T.self) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ def: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? def
    }
    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
    func flexBool(_ key: Key, _ def: Bool = false) -> Bool {
        if let b: Bool = optional(key) { return b }
        if let i: Int = optional(key) { return i != 0 }
        if let s: String = optional(key) {
            return s == "1" || s.caseInsensitiveCompare("true") == .orderedSame
        }
        return def
    }
    func flexInt64(_ key: Key, _ def: Int64 = 0) -> Int64 {
        if let i: Int64 = optional(key) { return i }
        if let s: String = optional(key), let i = Int64(s) { return i }
        return def
    }
}

struct MailItem: Codable, Identifiable, Equatable {
    let id: Int64
    var subject: String
    var snippet: String
    var sender: String
    var fromName: String
    var fromEmail: String
    var to: String
    var message: String?
    var createdAt: String
    var read: Bool
    var important: Bool
    var tagName: String?
    var tagColor: String?
    var folder: String
    var hasAttachments: Bool

    enum CodingKeys: String, CodingKey {
        case id, subject, snippet, sender
        case fromName = "from_name"
        case fromEmail = "from_email"
        case to, message
        case createdAt = "created_at"
        case read, important
        case tagName = "tag_name"
        case tagColor = "tag_color"
        case folder, hasAttachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = c.flexInt64(.id)
        subject       = c.value(.subject, "")
        snippet       = c.value(.snippet, "")
        sender        = c.value(.sender, "")
        fromName      = c.value(.fromName, "")
        fromEmail     = c.value(.fromEmail, "")
        to            = c.value(.to, "")
        message       = c.optional(.message)
        createdAt     = c.value(.createdAt, "")
        read          = c.flexBool(.read)
        important     = c.flexBool(.important)
        tagName       = c.optional(.tagName)
        tagColor      = c.optional(.tagColor)
        folder        = c.value(.folder, "inbox")
        hasAttachments = c.flexBool(.hasAttachments)
    }

    func displayName() -> String {
        if !fromName.isEmpty { return fromName }
        if !sender.isEmpty { return sender }
        if !fromEmail.isEmpty { return fromEmail }
        return "Неизвестный"
    }

    func displaySubject() -> String {
        if !subject.isEmpty { return subject }
        if !snippet.isEmpty { return snippet }
        return "Без темы"
    }
}

struct Attachment: Codable, Identifiable, Equatable {
    var id: Int64
    var fileName: String
    var fileSize: Int64
    var fileExtension: String
    var content: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case fileName = "file_name"
        case fileSize = "file_size"
        case fileExtension = "extension"
        case content
        case createdAt = "created_at"
    }

    init(id: Int64 = 0, fileName: String = "", fileSize: Int64 = 0,
         fileExtension: String = "", content: String? = nil, createdAt: String = "") {
        self.id = id; self.fileName = fileName; self.fileSize = fileSize
        self.fileExtension = fileExtension; self.content = content; self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = c.flexInt64(.id)
        fileName      = c.value(.fileName, "")
        fileSize      = c.flexInt64(.fileSize)
        fileExtension = c.value(.fileExtension, "")
        content       = c.optional(.content)
        createdAt     = c.value(.createdAt, "")
    }
}

struct MailDetails: Codable, Equatable {
    var id: Int64
    var subject: String?
    var snippet: String?
    var sender: String?
    var fromName: String?
    var fromEmail: String?
    var to: String?
    var message: String?
    var createdAt: String?
    var read: Bool
    var attachments: [Attachment]

    enum CodingKeys: String, CodingKey {
        case id, subject, snippet, sender
        case fromName = "from_name"
        case fromEmail = "from_email"
        case to, message
        case createdAt = "created_at"
        case read, attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = c.flexInt64(.id)
        subject     = c.optional(.subject)
        snippet     = c.optional(.snippet)
        sender      = c.optional(.sender)
        fromName    = c.optional(.fromName)
        fromEmail   = c.optional(.fromEmail)
        to          = c.optional(.to)
        message     = c.optional(.message)
        createdAt   = c.optional(.createdAt)
        read        = c.flexBool(.read)
        attachments = (c.optional(.attachments) ?? [Attachment?]()).compactMap { $0 }
    }

    func validAttachments() -> [Attachment] {
        attachments.filter { !$0.fileName.isEmpty }
    }
}

struct Folder: Codable, Identifiable, Equatable {
    let id: Int64
    var name: String
    var from: String?
    var contains: String?
    var unreadCount: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt64(.id)
        name = c.value(.name, "")
        from = c.optional(.from)
        contains = c.optional(.contains)
        unreadCount = Int(c.flexInt64(.unreadCount))
    }
    enum CodingKeys: String, CodingKey { case id, name, from, contains, unreadCount }
}

struct Tag: Codable, Identifiable, Equatable {
    let id: Int64
    var name: String
    var color: String
    var from: String?
    var contains: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt64(.id)
        name = c.value(.name, "")
        color = c.value(.color, "")
        from = c.optional(.from)
        contains = c.optional(.contains)
    }
    enum CodingKeys: String, CodingKey { case id, name, color, from, contains }
}

struct FilterItem: Codable, Identifiable, Equatable {
    let id: Int64
    var from: String
    var contains: String
    var folder: Int64?
    var action: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt64(.id)
        from = c.value(.from, "")
        contains = c.value(.contains, "")
        folder = c.optional(.folder)
        action = c.value(.action, "move")
    }
    enum CodingKeys: String, CodingKey { case id, from, contains, folder, action }
}

struct AliasAddress: Codable, Identifiable, Equatable {
    let id: Int64
    var email: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt64(.id)
        email = c.value(.email, "")
    }
    enum CodingKeys: String, CodingKey { case id, email }
}

struct UserAccount: Codable, Equatable {
    var email: String
    var token: String
    var firstName: String = ""
    var lastName: String = ""
    var signature: String = ""
    var signatureReply: Bool = true
    var signatureNew: Bool = true
    var twoFactor: Bool = false
    var reserveEmail: String? = nil
    var deletedAt: String? = nil
    var role: Int = 1
}

struct SecurityInfo: Codable, Equatable {
    var twoFactor: Bool = false
    var reserveEmail: String? = nil
    var deletedAt: String? = nil
}

struct FeedbackItem: Codable, Identifiable, Equatable {
    let id: Int64
    var firstName: String
    var type: String
    var subject: String
    var message: String
    var support: String?
    var read: Bool
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case type, subject, message, support, read
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexInt64(.id)
        firstName = c.value(.firstName, "")
        type = c.value(.type, "question")
        subject = c.value(.subject, "")
        message = c.value(.message, "")
        support = c.optional(.support)
        read = c.flexBool(.read)
        updatedAt = c.value(.updatedAt, "")
    }
}

struct TwoFactorQrData: Codable, Equatable {
    var secret: String = ""
    var qr: String = ""
    var qrImage: String = ""
}

struct RequestPayload: Encodable {
    let service: String
    let action: String
    var token: String = ""
    var currentLang: String = AppLanguage.currentCode
    var params: JSONValue? = nil
    var data: JSONValue? = nil
    var searchText: String? = nil
    var lastMailId: Int64? = nil
    var page: Int? = nil
    var draft: Bool? = nil
    var pageId: String? = nil

    enum CodingKeys: String, CodingKey {
        case service, action, token, params, data, draft
        case currentLang = "current_lang"
        case searchText = "search_text"
        case lastMailId = "last_mail_id"
        case page
        case pageId = "page_id"
    }
}

struct ApiResponse: Decodable {
    let status: Int?
    let message: String?
    let data: JSONValue?
    let token: String?
    let service: String?
    let action: String?
    let error: String?
    let total: JSONValue?

    let mails: [MailItem]?
    let folders: [Folder]?
    let tags: [Tag]?
    let filters: [FilterItem]?
    let addresses: [AliasAddress]?
    let questions: [FeedbackItem]?
    let lastMailId: Int64?
    let nothingChanged: Bool?

    let id: Int64?
    let email: String?
    let firstName: String?
    let lastName: String?
    let signature: String?
    let signatureReply: Bool?
    let signatureNew: Bool?
    let twoFactor: String?
    let reserveEmail: String?
    let deletedAt: String?
    let storageUsed: Double?
    let storageTotal: Int64?

    let qr: String?
    let qrImage: String?
    let secret: String?

    enum CodingKeys: String, CodingKey {
        case status, message, data, token, service, action, error, total
        case mails, folders, tags, filters, addresses, questions
        case lastMailId = "last_mail_id"
        case nothingChanged = "nothing_changed"
        case id, email
        case firstName = "first_name"
        case lastName = "last_name"
        case signature
        case signatureReply = "signature_reply"
        case signatureNew = "signature_new"
        case twoFactor = "two_factor"
        case reserveEmail = "reserve_email"
        case deletedAt = "deleted_at"
        case storageUsed = "storage_used"
        case storageTotal = "storage_total"
        case qr
        case qrImage = "qr_image"
        case secret
    }

    init(
        status: Int? = nil, message: String? = nil, data: JSONValue? = nil,
        token: String? = nil, service: String? = nil, action: String? = nil,
        error: String? = nil, total: JSONValue? = nil,
        mails: [MailItem]? = nil, folders: [Folder]? = nil, tags: [Tag]? = nil,
        filters: [FilterItem]? = nil, addresses: [AliasAddress]? = nil,
        questions: [FeedbackItem]? = nil, lastMailId: Int64? = nil,
        nothingChanged: Bool? = nil, id: Int64? = nil, email: String? = nil,
        firstName: String? = nil, lastName: String? = nil, signature: String? = nil,
        signatureReply: Bool? = nil, signatureNew: Bool? = nil, twoFactor: String? = nil,
        reserveEmail: String? = nil, deletedAt: String? = nil, storageUsed: Double? = nil,
        storageTotal: Int64? = nil, qr: String? = nil, qrImage: String? = nil, secret: String? = nil
    ) {
        self.status = status; self.message = message; self.data = data; self.token = token
        self.service = service; self.action = action; self.error = error; self.total = total
        self.mails = mails; self.folders = folders; self.tags = tags; self.filters = filters
        self.addresses = addresses; self.questions = questions; self.lastMailId = lastMailId
        self.nothingChanged = nothingChanged; self.id = id; self.email = email
        self.firstName = firstName; self.lastName = lastName; self.signature = signature
        self.signatureReply = signatureReply; self.signatureNew = signatureNew
        self.twoFactor = twoFactor; self.reserveEmail = reserveEmail; self.deletedAt = deletedAt
        self.storageUsed = storageUsed; self.storageTotal = storageTotal
        self.qr = qr; self.qrImage = qrImage; self.secret = secret
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decodeIfPresent(Int.self, forKey: .status) {
            status = i
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .status) {
            status = Int(s ?? "")
        } else { status = nil }

        message        = try? c.decodeIfPresent(String.self, forKey: .message) ?? nil
        data           = try? c.decodeIfPresent(JSONValue.self, forKey: .data) ?? nil
        token          = try? c.decodeIfPresent(String.self, forKey: .token) ?? nil
        service        = try? c.decodeIfPresent(String.self, forKey: .service) ?? nil
        action         = try? c.decodeIfPresent(String.self, forKey: .action) ?? nil
        error          = try? c.decodeIfPresent(String.self, forKey: .error) ?? nil
        total          = try? c.decodeIfPresent(JSONValue.self, forKey: .total) ?? nil
        mails          = try? c.decodeIfPresent([MailItem].self, forKey: .mails) ?? nil
        folders        = try? c.decodeIfPresent([Folder].self, forKey: .folders) ?? nil
        tags           = try? c.decodeIfPresent([Tag].self, forKey: .tags) ?? nil
        filters        = try? c.decodeIfPresent([FilterItem].self, forKey: .filters) ?? nil
        addresses      = try? c.decodeIfPresent([AliasAddress].self, forKey: .addresses) ?? nil
        questions      = try? c.decodeIfPresent([FeedbackItem].self, forKey: .questions) ?? nil
        lastMailId     = try? c.decodeIfPresent(Int64.self, forKey: .lastMailId) ?? nil
        nothingChanged = try? c.decodeIfPresent(Bool.self, forKey: .nothingChanged) ?? nil
        id             = try? c.decodeIfPresent(Int64.self, forKey: .id) ?? nil
        email          = try? c.decodeIfPresent(String.self, forKey: .email) ?? nil
        firstName      = try? c.decodeIfPresent(String.self, forKey: .firstName) ?? nil
        lastName       = try? c.decodeIfPresent(String.self, forKey: .lastName) ?? nil
        signature      = try? c.decodeIfPresent(String.self, forKey: .signature) ?? nil
        signatureReply = try? c.decodeIfPresent(Bool.self, forKey: .signatureReply) ?? nil
        signatureNew   = try? c.decodeIfPresent(Bool.self, forKey: .signatureNew) ?? nil
        twoFactor      = try? c.decodeIfPresent(String.self, forKey: .twoFactor) ?? nil
        reserveEmail   = try? c.decodeIfPresent(String.self, forKey: .reserveEmail) ?? nil
        deletedAt      = try? c.decodeIfPresent(String.self, forKey: .deletedAt) ?? nil
        storageUsed    = try? c.decodeIfPresent(Double.self, forKey: .storageUsed) ?? nil
        storageTotal   = try? c.decodeIfPresent(Int64.self, forKey: .storageTotal) ?? nil
        qr             = try? c.decodeIfPresent(String.self, forKey: .qr) ?? nil
        qrImage        = try? c.decodeIfPresent(String.self, forKey: .qrImage) ?? nil
        secret         = try? c.decodeIfPresent(String.self, forKey: .secret) ?? nil
    }

    func isSuccess() -> Bool { status == 1 }

    static func failure(_ message: String) -> ApiResponse {
        ApiResponse(status: 0, message: message)
    }

    func extractToken() -> String? {
        if let t = token, !t.isEmpty { return t }
        guard let data = data else { return nil }
        if case .string(let s) = data { return s }
        if let t = data["token"]?.stringValue { return t }
        return nil
    }

    func mailDetails() -> MailDetails? { data?.decoded(MailDetails.self) }

    func twoFactorQrData() -> TwoFactorQrData? {
        guard let qr = qr, let secret = secret else { return nil }
        return TwoFactorQrData(secret: secret, qr: qr, qrImage: qrImage ?? "")
    }

    func decodeData<T: Decodable>(as type: T.Type) -> T? { data?.decoded(T.self) }
}