//
//  ApiClient.swift
//  XyecocMail
//
//  Native URLSession port of Android `data/api/ApiService.kt`.
//  Everything is a single JSON-RPC call: POST {baseURL}/request with a
//  `RequestPayload` body, returning the fat `ApiResponse` union.
//
//  Like the Kotlin original, `request(_:)` never throws — network/HTTP/parse
//  failures are folded into `ApiResponse.failure(...)` (status = 0) so callers
//  can uniformly branch on `isSuccess()`.
//

import Foundation

final class ApiClient {

    static let shared = ApiClient()

    let baseURL: String
    let cdnURL: String

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: String = "https://api.xyecoc.com",
         cdnURL: String = "https://cdn.xyecoc.com") {
        self.baseURL = baseURL
        self.cdnURL = cdnURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20     // matches OkHttp read timeout
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - JSON-RPC

    /// POST {baseURL}/request with the given payload.
    func request(_ payload: RequestPayload) async -> ApiResponse {
        guard let url = URL(string: "\(baseURL)/request") else {
            return .failure("Invalid URL")
        }

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(payload)

            #if DEBUG
            if let body = req.httpBody, let s = String(data: body, encoding: .utf8) {
                print("[XyecocApi] → \(payload.service)/\(payload.action) \(s)")
            }
            #endif

            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse

            #if DEBUG
            print("[XyecocApi] ← \(http?.statusCode ?? -1) \(String(data: data, encoding: .utf8) ?? "<binary>")")
            #endif

            guard let http = http,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty else {
                return .failure("HTTP error: \(http?.statusCode ?? -1)")
            }

            return try decoder.decode(ApiResponse.self, from: data)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Raw mail HTML from the CDN

    /// Port of `MailRepository.fetchMailBodyHtml`. Fetches the rendered HTML
    /// body from the CDN; token is passed both in the path/query and as a
    /// cookie, exactly as the Android client does. Returns "" on any failure
    /// or a literal "404" body.
    func fetchMailBodyHtml(mailId: Int64, token: String) async -> String {
        guard let url = URL(string: "\(cdnURL)/mail/\(token)/\(mailId)?token=\(token)") else {
            return ""
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("authorization=\(token)", forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return "" }
            let body = String(data: data, encoding: .utf8) ?? ""
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed == "404" || trimmed.isEmpty) ? "" : body
        } catch {
            return ""
        }
    }
}
