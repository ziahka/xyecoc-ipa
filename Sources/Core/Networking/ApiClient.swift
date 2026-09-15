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

    #if DEBUG
    private static let sensitiveKeys = ["password", "password_old", "password_new", "password_repeat", "token", "secret", "code"]
    private func redacted(_ s: String) -> String {
        var out = s
        for key in Self.sensitiveKeys {
            out = out.replacingOccurrences(
                of: "\"\(key)\"\\s*:\\s*\"[^\"]*\"",
                with: "\"\(key)\":\"***\"",
                options: .regularExpression)
        }
        return out
    }
    #endif

    /// POST {baseURL}/request with the given payload.
    /// If the server responds with an auth error and a valid token exists,
    /// one automatic refresh-token retry is attempted before returning failure.
    func request(_ payload: RequestPayload, allowRetry: Bool = true) async -> ApiResponse {
        let response = await rawRequest(payload)

        // Auto-refresh: if the response looks like an expired-token error and
        // the caller didn't already retry, attempt a single token refresh.
        if allowRetry,
           !payload.token.isEmpty,
           Self.isAuthError(response),
           let refreshed = await attemptTokenRefresh(expiredToken: payload.token) {
            var retryPayload = payload
            retryPayload.token = refreshed
            return await rawRequest(retryPayload)
        }

        // Специфика сервера: mail/default с мёртвой сессией возвращает
        // «эхо»-конверт без статуса, ошибки и данных (проверено curl'ом):
        // {"params":...,"service":"mail","action":"default","security":"private"}
        // Клиент видит «успех без данных» и молчит. Лечим: трактуем как
        // auth-сбой, пробуем refresh-token, ретраим; если эхо повторилось —
        // превращаем его в явную ошибку, чтобы UI показал причину.
        if Self.isMailDefaultEcho(payload, response) {
            if allowRetry, !payload.token.isEmpty,
               let refreshed = await attemptTokenRefresh(expiredToken: payload.token) {
                var retryPayload = payload
                retryPayload.token = refreshed
                let retried = await rawRequest(retryPayload)
                if !Self.isMailDefaultEcho(retryPayload, retried) { return retried }
            }
            return ApiResponse(status: 0, service: response.service,
                               action: response.action, error: "authenticate error")
        }
        return response
    }

    /// Эхо-конверт мёртвой сессии: ни ошибки, ни данных, ни статуса.
    private static func isMailDefaultEcho(_ payload: RequestPayload, _ r: ApiResponse) -> Bool {
        payload.service == "mail" && payload.action == "default"
            && r.error == nil && r.mails == nil && r.folders == nil && r.tags == nil
            && r.status == nil && r.message == nil && r.data == nil
    }

    // MARK: - Internals

    private func rawRequest(_ payload: RequestPayload) async -> ApiResponse {
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
                print("[XyecocApi] → \(payload.service)/\(payload.action) \(redacted(s))")
            }
            #endif

            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse

            #if DEBUG
            print("[XyecocApi] ← \(http?.statusCode ?? -1) \(redacted(String(data: data, encoding: .utf8) ?? "<binary>"))")
            #endif

            if !data.isEmpty, let decoded = try? decoder.decode(ApiResponse.self, from: data) {
                return decoded
            }

            guard let http = http,
                  (200..<300).contains(http.statusCode) else {
                return .failure("HTTP error: \(http?.statusCode ?? -1)")
            }

            return .failure("Пустой ответ сервера")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Heuristic: the server returns status 0 with a message hinting at auth failure,
    /// or an HTTP 401, when the token is expired / invalid.
    private static func isAuthError(_ r: ApiResponse) -> Bool {
        if r.status == 0, let msg = (r.message ?? r.error)?.lowercased() {
            return msg.contains("token") || msg.contains("auth") || msg.contains("unauthorized")
                || msg.contains("expired") || msg.contains("истек")
        }
        return false
    }

    /// Ask the server for a fresh token. Returns the new token on success, nil otherwise.
    private func attemptTokenRefresh(expiredToken: String) async -> String? {
        let payload = RequestPayload(
            service: "account",
            action: "refresh-token",
            data: .object(["token": .string(expiredToken)])
        )
        let response = await rawRequest(payload)
        guard response.isSuccess(), let newToken = response.extractToken(), !newToken.isEmpty else {
            return nil
        }
        KeychainManager.shared.updateActiveToken(newToken)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "token_refreshed_at")
        return newToken
    }

    private static let sessionRefreshInterval: TimeInterval = 15 * 60

    /// Проактивное продление сессии раз в 15 минут. Сервер гасит токены
    /// быстро, а mail/default при мёртвой сессии отвечает эхой без ошибки —
    /// поэтому продлеваем заранее, пока старый токен ещё жив.
    func preemptiveSessionRefresh() async {
        guard !keychainToken().isEmpty else { return }
        let last = UserDefaults.standard.double(forKey: "token_refreshed_at")
        guard Date().timeIntervalSince1970 - last >= Self.sessionRefreshInterval else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "token_refreshed_at")
        _ = await attemptTokenRefresh(expiredToken: keychainToken())
    }

    private func keychainToken() -> String {
        KeychainManager.shared.activeToken() ?? ""
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
