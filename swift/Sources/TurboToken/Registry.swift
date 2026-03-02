import Foundation

/// Specification for a BPE encoding.
public struct EncodingSpec: Sendable {
    public let name: String
    public let rankFileURL: URL
    public let patStr: String
    public let specialTokens: [String: Int]
    public let nVocab: Int
}

/// Registry of known encodings and model-to-encoding mappings.
public enum Registry {
    // MARK: - Pattern Strings

    private static let r50kPatStr =
        #"'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s"#

    private static let cl100kPatStr =
        #"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s"#

    private static let o200kPatStr = [
        #"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?"#,
        #"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?"#,
        #"\p{N}{1,3}"#,
        #" ?[^\s\p{L}\p{N}]+[\r\n/]*"#,
        #"\s*[\r\n]+"#,
        #"\s+(?!\S)"#,
        #"\s+"#,
    ].joined(separator: "|")

    // MARK: - Special Token Constants

    private static let endOfText = "<|endoftext|>"
    private static let fimPrefix = "<|fim_prefix|>"
    private static let fimMiddle = "<|fim_middle|>"
    private static let fimSuffix = "<|fim_suffix|>"
    private static let endOfPrompt = "<|endofprompt|>"

    // MARK: - Encoding Specs

    private static let encodingSpecs: [String: EncodingSpec] = [
        "o200k_base": EncodingSpec(
            name: "o200k_base",
            rankFileURL: URL(string: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken")!,
            patStr: o200kPatStr,
            specialTokens: [endOfText: 199999, endOfPrompt: 200018],
            nVocab: 200019
        ),
        "cl100k_base": EncodingSpec(
            name: "cl100k_base",
            rankFileURL: URL(string: "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken")!,
            patStr: cl100kPatStr,
            specialTokens: [
                endOfText: 100257,
                fimPrefix: 100258,
                fimMiddle: 100259,
                fimSuffix: 100260,
                endOfPrompt: 100276,
            ],
            nVocab: 100277
        ),
        "p50k_base": EncodingSpec(
            name: "p50k_base",
            rankFileURL: URL(string: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken")!,
            patStr: r50kPatStr,
            specialTokens: [endOfText: 50256],
            nVocab: 50281
        ),
        "r50k_base": EncodingSpec(
            name: "r50k_base",
            rankFileURL: URL(string: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken")!,
            patStr: r50kPatStr,
            specialTokens: [endOfText: 50256],
            nVocab: 50257
        ),
        "gpt2": EncodingSpec(
            name: "gpt2",
            rankFileURL: URL(string: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken")!,
            patStr: r50kPatStr,
            specialTokens: [endOfText: 50256],
            nVocab: 50257
        ),
        "p50k_edit": EncodingSpec(
            name: "p50k_edit",
            rankFileURL: URL(string: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken")!,
            patStr: r50kPatStr,
            specialTokens: [endOfText: 50256],
            nVocab: 50281
        ),
        "o200k_harmony": EncodingSpec(
            name: "o200k_harmony",
            rankFileURL: URL(string: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken")!,
            patStr: o200kPatStr,
            specialTokens: [endOfText: 199999, endOfPrompt: 200018],
            nVocab: 200019
        ),
    ]

    // MARK: - Model Mappings

    private static let modelToEncodingMap: [String: String] = [
        "o1": "o200k_base",
        "o3": "o200k_base",
        "o4-mini": "o200k_base",
        "gpt-5": "o200k_base",
        "gpt-4.1": "o200k_base",
        "gpt-4o": "o200k_base",
        "gpt-4o-mini": "o200k_base",
        "gpt-4.1-mini": "o200k_base",
        "gpt-4.1-nano": "o200k_base",
        "gpt-oss-120b": "o200k_harmony",
        "gpt-4": "cl100k_base",
        "gpt-3.5-turbo": "cl100k_base",
        "gpt-3.5": "cl100k_base",
        "gpt-35-turbo": "cl100k_base",
        "davinci-002": "cl100k_base",
        "babbage-002": "cl100k_base",
        "text-embedding-ada-002": "cl100k_base",
        "text-embedding-3-small": "cl100k_base",
        "text-embedding-3-large": "cl100k_base",
        "text-davinci-003": "p50k_base",
        "text-davinci-002": "p50k_base",
        "text-davinci-001": "r50k_base",
        "text-curie-001": "r50k_base",
        "text-babbage-001": "r50k_base",
        "text-ada-001": "r50k_base",
        "davinci": "r50k_base",
        "curie": "r50k_base",
        "babbage": "r50k_base",
        "ada": "r50k_base",
        "code-davinci-002": "p50k_base",
        "code-davinci-001": "p50k_base",
        "code-cushman-002": "p50k_base",
        "code-cushman-001": "p50k_base",
        "davinci-codex": "p50k_base",
        "cushman-codex": "p50k_base",
        "text-davinci-edit-001": "p50k_edit",
        "code-davinci-edit-001": "p50k_edit",
        "text-similarity-davinci-001": "r50k_base",
        "text-similarity-curie-001": "r50k_base",
        "text-similarity-babbage-001": "r50k_base",
        "text-similarity-ada-001": "r50k_base",
        "text-search-davinci-doc-001": "r50k_base",
        "text-search-curie-doc-001": "r50k_base",
        "text-search-babbage-doc-001": "r50k_base",
        "text-search-ada-doc-001": "r50k_base",
        "code-search-babbage-code-001": "r50k_base",
        "code-search-ada-code-001": "r50k_base",
        "gpt2": "gpt2",
        "gpt-2": "r50k_base",
    ]

    private static let modelPrefixToEncoding: [(String, String)] = [
        ("o1-", "o200k_base"),
        ("o3-", "o200k_base"),
        ("o4-mini-", "o200k_base"),
        ("gpt-5-", "o200k_base"),
        ("gpt-4.5-", "o200k_base"),
        ("gpt-4.1-", "o200k_base"),
        ("chatgpt-4o-", "o200k_base"),
        ("gpt-4o-", "o200k_base"),
        ("gpt-oss-", "o200k_harmony"),
        ("gpt-4-", "cl100k_base"),
        ("gpt-3.5-turbo-", "cl100k_base"),
        ("gpt-35-turbo-", "cl100k_base"),
        ("ft:gpt-4o", "o200k_base"),
        ("ft:gpt-4", "cl100k_base"),
        ("ft:gpt-3.5-turbo", "cl100k_base"),
        ("ft:davinci-002", "cl100k_base"),
        ("ft:babbage-002", "cl100k_base"),
    ]

    // MARK: - Public API

    /// Get the encoding spec for a given encoding name.
    public static func getEncodingSpec(name: String) throws -> EncodingSpec {
        guard let spec = encodingSpecs[name] else {
            let supported = listEncodingNames().joined(separator: ", ")
            throw TurboTokenError.unknownEncoding("Unknown encoding '\(name)'. Supported: \(supported)")
        }
        return spec
    }

    /// Map a model name to its encoding name.
    public static func modelToEncoding(model: String) throws -> String {
        if let encoding = modelToEncodingMap[model] {
            return encoding
        }
        for (prefix, encoding) in modelPrefixToEncoding {
            if model.hasPrefix(prefix) {
                return encoding
            }
        }
        throw TurboTokenError.unknownModel(
            "Could not automatically map '\(model)' to an encoding. Use getEncoding(name:) to select one explicitly."
        )
    }

    /// List all known encoding names, sorted.
    public static func listEncodingNames() -> [String] {
        encodingSpecs.keys.sorted()
    }
}
