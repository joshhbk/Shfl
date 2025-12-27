import Foundation
import Testing
@testable import Shfl

@Suite("AutofillSource Protocol Tests")
struct AutofillSourceTests {
    @Test("Protocol exists and can be referenced")
    func protocolExists() {
        // This test verifies the protocol compiles and can be used as a type
        let _: (any AutofillSource)? = nil
    }
}
