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
}
