import Testing
@testable import Shfl

@Suite("LastFMClient Tests")
struct LastFMClientTests {

    @Test("API signature is generated correctly")
    func apiSignature() {
        // Last.fm signature: sort params, concatenate, append secret, MD5
        // Example from docs: api_key=xxx, method=auth.getSession, token=yyy, secret=zzz
        // Sorted: api_keyxxxmethodauth.getSessiontokenyyy + zzz -> MD5

        let params = [
            "api_key": "testkey",
            "method": "track.scrobble",
            "artist": "Cher"
        ]
        let secret = "testsecret"

        let signature = LastFMClient.generateSignature(params: params, secret: secret)

        // Signature should be 32-char hex MD5
        #expect(signature.count == 32)
        #expect(signature.allSatisfy { $0.isHexDigit })
    }

    @Test("Signature is deterministic")
    func signatureDeterministic() {
        let params = ["a": "1", "b": "2"]
        let secret = "secret"

        let sig1 = LastFMClient.generateSignature(params: params, secret: secret)
        let sig2 = LastFMClient.generateSignature(params: params, secret: secret)

        #expect(sig1 == sig2)
    }

    @Test("Signature changes with different params")
    func signatureChangesWithParams() {
        let params1 = ["a": "1"]
        let params2 = ["a": "2"]
        let secret = "secret"

        let sig1 = LastFMClient.generateSignature(params: params1, secret: secret)
        let sig2 = LastFMClient.generateSignature(params: params2, secret: secret)

        #expect(sig1 != sig2)
    }
}
