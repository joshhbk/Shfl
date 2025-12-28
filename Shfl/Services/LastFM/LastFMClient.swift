import Foundation
import CryptoKit

actor LastFMClient {
    private let apiKey: String
    private let sharedSecret: String
    private var sessionKey: String?

    private let baseURL = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    init(apiKey: String, sharedSecret: String) {
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
    }

    func setSessionKey(_ key: String?) {
        self.sessionKey = key
    }

    // MARK: - Signature Generation (static for testability)

    static func generateSignature(params: [String: String], secret: String) -> String {
        // Sort parameters alphabetically by key
        let sortedParams = params.sorted { $0.key < $1.key }

        // Concatenate as key1value1key2value2...
        var signatureBase = ""
        for (key, value) in sortedParams {
            signatureBase += key + value
        }

        // Append secret
        signatureBase += secret

        // MD5 hash
        let digest = Insecure.MD5.hash(data: Data(signatureBase.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - Request Building

    func buildScrobbleRequest(_ event: ScrobbleEvent) -> URLRequest {
        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sessionKey ?? "",
            "track[0]": event.track,
            "artist[0]": event.artist,
            "album[0]": event.album,
            "timestamp[0]": String(Int(event.timestamp.timeIntervalSince1970)),
            "duration[0]": String(event.durationSeconds)
        ]

        let signature = Self.generateSignature(params: params, secret: sharedSecret)
        params["api_sig"] = signature
        params["format"] = "json"

        return buildPOSTRequest(params: params)
    }

    func buildNowPlayingRequest(_ event: ScrobbleEvent) -> URLRequest {
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sessionKey ?? "",
            "track": event.track,
            "artist": event.artist,
            "album": event.album,
            "duration": String(event.durationSeconds)
        ]

        let signature = Self.generateSignature(params: params, secret: sharedSecret)
        params["api_sig"] = signature
        params["format"] = "json"

        return buildPOSTRequest(params: params)
    }

    private func buildPOSTRequest(params: [String: String]) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        return request
    }
}
