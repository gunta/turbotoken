import CTurboToken
import Foundation

/// A BPE encoding instance backed by a rank file.
public final class Encoding: @unchecked Sendable {
    /// The encoding name (e.g. "cl100k_base").
    public let name: String

    /// The encoding spec used to create this instance.
    public let spec: EncodingSpec

    /// Raw rank file bytes used by the FFI layer.
    public let rankPayload: Data

    internal init(name: String, spec: EncodingSpec, rankPayload: Data) {
        self.name = name
        self.spec = spec
        self.rankPayload = rankPayload
    }

    // MARK: - Encode

    /// Encode text to BPE token IDs.
    public func encode(_ text: String) throws -> [UInt32] {
        let textBytes = Array(text.utf8)
        return try rankPayload.withUnsafeBytes { rankPtr in
            let rankBase = rankPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let rankLen = rankPtr.count
            return try callTwoPassUInt32(
                sizeQuery: {
                    Int(turbotoken_encode_bpe_from_ranks(
                        rankBase, rankLen,
                        textBytes, textBytes.count,
                        nil, 0))
                },
                fill: { buf, cap in
                    Int(turbotoken_encode_bpe_from_ranks(
                        rankBase, rankLen,
                        textBytes, textBytes.count,
                        buf, cap))
                }
            )
        }
    }

    // MARK: - Decode

    /// Decode BPE token IDs back to a UTF-8 string.
    public func decode(_ tokens: [UInt32]) throws -> String {
        let bytes: [UInt8] = try rankPayload.withUnsafeBytes { rankPtr in
            let rankBase = rankPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let rankLen = rankPtr.count
            return try callTwoPassUInt8(
                sizeQuery: {
                    Int(turbotoken_decode_bpe_from_ranks(
                        rankBase, rankLen,
                        tokens, tokens.count,
                        nil, 0))
                },
                fill: { buf, cap in
                    Int(turbotoken_decode_bpe_from_ranks(
                        rankBase, rankLen,
                        tokens, tokens.count,
                        buf, cap))
                }
            )
        }
        guard let result = String(bytes: bytes, encoding: .utf8) else {
            throw TurboTokenError.decodingFailed("Decoded bytes are not valid UTF-8")
        }
        return result
    }

    // MARK: - Count

    /// Count the number of BPE tokens for the given text.
    public func count(_ text: String) throws -> Int {
        let textBytes = Array(text.utf8)
        return try rankPayload.withUnsafeBytes { rankPtr in
            let rankBase = rankPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let rankLen = rankPtr.count
            let result = Int(turbotoken_count_bpe_from_ranks(
                rankBase, rankLen,
                textBytes, textBytes.count))
            guard result >= 0 else {
                throw TurboTokenError.encodingFailed("count returned error code \(result)")
            }
            return result
        }
    }

    /// Alias for `count(_:)`.
    public func countTokens(_ text: String) throws -> Int {
        return try count(text)
    }

    // MARK: - Token Limit

    /// Check if text is within a token limit. Returns the token count if within limit.
    /// Throws `TurboTokenError.tokenLimitExceeded` if the text exceeds the limit.
    public func isWithinTokenLimit(_ text: String, limit: Int) throws -> Int {
        let textBytes = Array(text.utf8)
        return try rankPayload.withUnsafeBytes { rankPtr in
            let rankBase = rankPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let rankLen = rankPtr.count
            let result = Int(turbotoken_is_within_token_limit_bpe_from_ranks(
                rankBase, rankLen,
                textBytes, textBytes.count,
                limit))
            if result == -2 {
                throw TurboTokenError.tokenLimitExceeded(limit: limit)
            }
            guard result >= 0 else {
                throw TurboTokenError.encodingFailed("isWithinTokenLimit returned error code \(result)")
            }
            return result
        }
    }

    // MARK: - Chat

    /// Encode a chat conversation to token IDs.
    public func encodeChat(_ messages: [ChatMessage], options: ChatOptions = ChatOptions()) throws -> [UInt32] {
        let text = formatChat(messages, options: options)
        return try encode(text)
    }

    /// Count tokens in a chat conversation.
    public func countChat(_ messages: [ChatMessage], options: ChatOptions = ChatOptions()) throws -> Int {
        let text = formatChat(messages, options: options)
        return try count(text)
    }

    /// Check if a chat conversation is within a token limit.
    public func isChatWithinTokenLimit(_ messages: [ChatMessage], limit: Int, options: ChatOptions = ChatOptions()) throws -> Int {
        let text = formatChat(messages, options: options)
        return try isWithinTokenLimit(text, limit: limit)
    }

    // MARK: - File Operations

    /// Encode a file's contents to BPE token IDs.
    public func encodeFilePath(_ path: String) throws -> [UInt32] {
        let pathBytes = Array(path.utf8)
        return try rankPayload.withUnsafeBytes { rankPtr in
            let rankBase = rankPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let rankLen = rankPtr.count
            return try callTwoPassUInt32(
                sizeQuery: {
                    Int(turbotoken_encode_bpe_file_from_ranks(
                        rankBase, rankLen,
                        pathBytes, pathBytes.count,
                        nil, 0))
                },
                fill: { buf, cap in
                    Int(turbotoken_encode_bpe_file_from_ranks(
                        rankBase, rankLen,
                        pathBytes, pathBytes.count,
                        buf, cap))
                }
            )
        }
    }

    /// Count tokens in a file.
    public func countFilePath(_ path: String) throws -> Int {
        let pathBytes = Array(path.utf8)
        return try rankPayload.withUnsafeBytes { rankPtr in
            let rankBase = rankPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let rankLen = rankPtr.count
            let result = Int(turbotoken_count_bpe_file_from_ranks(
                rankBase, rankLen,
                pathBytes, pathBytes.count))
            guard result >= 0 else {
                throw TurboTokenError.encodingFailed("countFilePath returned error code \(result)")
            }
            return result
        }
    }

    /// Check if a file's content is within a token limit.
    public func isFilePathWithinTokenLimit(_ path: String, limit: Int) throws -> Int {
        let pathBytes = Array(path.utf8)
        return try rankPayload.withUnsafeBytes { rankPtr in
            let rankBase = rankPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let rankLen = rankPtr.count
            let result = Int(turbotoken_is_within_token_limit_bpe_file_from_ranks(
                rankBase, rankLen,
                pathBytes, pathBytes.count,
                limit))
            if result == -2 {
                throw TurboTokenError.tokenLimitExceeded(limit: limit)
            }
            guard result >= 0 else {
                throw TurboTokenError.encodingFailed("isFilePathWithinTokenLimit returned error code \(result)")
            }
            return result
        }
    }

    // MARK: - Static Factory

    /// Get an encoding by name (e.g. "cl100k_base", "o200k_base").
    public static func getEncoding(name: String) async throws -> Encoding {
        let spec = try Registry.getEncodingSpec(name: name)
        let rankData = try await RankCache.readRankFile(name: spec.name)
        return Encoding(name: spec.name, spec: spec, rankPayload: rankData)
    }

    /// Get the encoding for a model name (e.g. "gpt-4o", "gpt-3.5-turbo").
    public static func getEncodingForModel(model: String) async throws -> Encoding {
        let encodingName = try Registry.modelToEncoding(model: model)
        return try await getEncoding(name: encodingName)
    }
}
