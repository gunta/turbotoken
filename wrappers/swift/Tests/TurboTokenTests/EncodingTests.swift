import XCTest
@testable import TurboToken

final class EncodingTests: XCTestCase {
    func testListEncodings() {
        let names = Registry.listEncodingNames()
        XCTAssertTrue(names.contains("cl100k_base"))
        XCTAssertTrue(names.contains("o200k_base"))
        XCTAssertTrue(names.contains("r50k_base"))
        XCTAssertTrue(names.contains("p50k_base"))
        XCTAssertTrue(names.contains("gpt2"))
        XCTAssertTrue(names.contains("p50k_edit"))
        XCTAssertTrue(names.contains("o200k_harmony"))
        XCTAssertEqual(names.count, 7)
    }

    func testGetEncodingSpec() throws {
        let spec = try Registry.getEncodingSpec(name: "cl100k_base")
        XCTAssertEqual(spec.name, "cl100k_base")
        XCTAssertEqual(spec.nVocab, 100277)
        XCTAssertEqual(spec.specialTokens["<|endoftext|>"], 100257)
    }

    func testGetEncodingSpecUnknown() {
        XCTAssertThrowsError(try Registry.getEncodingSpec(name: "nonexistent")) { error in
            guard case TurboTokenError.unknownEncoding = error else {
                XCTFail("Expected unknownEncoding error")
                return
            }
        }
    }

    func testModelToEncoding() throws {
        XCTAssertEqual(try Registry.modelToEncoding(model: "gpt-4o"), "o200k_base")
        XCTAssertEqual(try Registry.modelToEncoding(model: "gpt-4"), "cl100k_base")
        XCTAssertEqual(try Registry.modelToEncoding(model: "gpt-3.5-turbo"), "cl100k_base")
        XCTAssertEqual(try Registry.modelToEncoding(model: "davinci"), "r50k_base")
        XCTAssertEqual(try Registry.modelToEncoding(model: "gpt2"), "gpt2")
    }

    func testModelToEncodingPrefix() throws {
        XCTAssertEqual(try Registry.modelToEncoding(model: "gpt-4o-2024-01-01"), "o200k_base")
        XCTAssertEqual(try Registry.modelToEncoding(model: "gpt-4-turbo-preview"), "cl100k_base")
        XCTAssertEqual(try Registry.modelToEncoding(model: "o1-preview"), "o200k_base")
    }

    func testModelToEncodingUnknown() {
        XCTAssertThrowsError(try Registry.modelToEncoding(model: "totally-unknown-model")) { error in
            guard case TurboTokenError.unknownModel = error else {
                XCTFail("Expected unknownModel error")
                return
            }
        }
    }

    func testVersion() {
        let version = ffiVersion()
        XCTAssertFalse(version.isEmpty)
    }

    func testEncodeDecodeRoundTrip() async throws {
        let enc = try await Encoding.getEncoding(name: "cl100k_base")
        let text = "Hello, world!"
        let tokens = try enc.encode(text)
        XCTAssertFalse(tokens.isEmpty)
        let decoded = try enc.decode(tokens)
        XCTAssertEqual(decoded, text)
    }

    func testCount() async throws {
        let enc = try await Encoding.getEncoding(name: "cl100k_base")
        let text = "Hello, world!"
        let tokens = try enc.encode(text)
        let count = try enc.count(text)
        XCTAssertEqual(count, tokens.count)
    }
}
