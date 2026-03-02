using System;
using System.Collections.Generic;
using System.Linq;

namespace TurboToken
{
    /// <summary>
    /// Specification for a BPE encoding.
    /// </summary>
    public sealed class EncodingSpec
    {
        public string Name { get; }
        public string RankFileUrl { get; }
        public string PatStr { get; }
        public IReadOnlyDictionary<string, int> SpecialTokens { get; }
        public int NVocab { get; }

        public EncodingSpec(string name, string rankFileUrl, string patStr, Dictionary<string, int> specialTokens, int nVocab)
        {
            Name = name;
            RankFileUrl = rankFileUrl;
            PatStr = patStr;
            SpecialTokens = specialTokens;
            NVocab = nVocab;
        }
    }

    /// <summary>
    /// Registry of known BPE encodings and model-to-encoding mappings.
    /// </summary>
    public static class Registry
    {
        private const string EndOfText = "<|endoftext|>";
        private const string FimPrefix = "<|fim_prefix|>";
        private const string FimMiddle = "<|fim_middle|>";
        private const string FimSuffix = "<|fim_suffix|>";
        private const string EndOfPrompt = "<|endofprompt|>";

        private static readonly string R50kPatStr =
            @"'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s";

        private static readonly string Cl100kPatStr =
            @"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s";

        private static readonly string O200kPatStr = string.Join("|", new[]
        {
            @"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
            @"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
            @"\p{N}{1,3}",
            @" ?[^\s\p{L}\p{N}]+[\r\n/]*",
            @"\s*[\r\n]+",
            @"\s+(?!\S)",
            @"\s+",
        });

        private static readonly Dictionary<string, EncodingSpec> EncodingSpecs = new Dictionary<string, EncodingSpec>
        {
            ["o200k_base"] = new EncodingSpec(
                "o200k_base",
                "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
                O200kPatStr,
                new Dictionary<string, int> { [EndOfText] = 199999, [EndOfPrompt] = 200018 },
                200019),
            ["cl100k_base"] = new EncodingSpec(
                "cl100k_base",
                "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
                Cl100kPatStr,
                new Dictionary<string, int>
                {
                    [EndOfText] = 100257,
                    [FimPrefix] = 100258,
                    [FimMiddle] = 100259,
                    [FimSuffix] = 100260,
                    [EndOfPrompt] = 100276,
                },
                100277),
            ["p50k_base"] = new EncodingSpec(
                "p50k_base",
                "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
                R50kPatStr,
                new Dictionary<string, int> { [EndOfText] = 50256 },
                50281),
            ["r50k_base"] = new EncodingSpec(
                "r50k_base",
                "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
                R50kPatStr,
                new Dictionary<string, int> { [EndOfText] = 50256 },
                50257),
            ["gpt2"] = new EncodingSpec(
                "gpt2",
                "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
                R50kPatStr,
                new Dictionary<string, int> { [EndOfText] = 50256 },
                50257),
            ["p50k_edit"] = new EncodingSpec(
                "p50k_edit",
                "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
                R50kPatStr,
                new Dictionary<string, int> { [EndOfText] = 50256 },
                50281),
            ["o200k_harmony"] = new EncodingSpec(
                "o200k_harmony",
                "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
                O200kPatStr,
                new Dictionary<string, int> { [EndOfText] = 199999, [EndOfPrompt] = 200018 },
                200019),
        };

        private static readonly Dictionary<string, string> ModelToEncodingMap = new Dictionary<string, string>
        {
            ["o1"] = "o200k_base",
            ["o3"] = "o200k_base",
            ["o4-mini"] = "o200k_base",
            ["gpt-5"] = "o200k_base",
            ["gpt-4.1"] = "o200k_base",
            ["gpt-4o"] = "o200k_base",
            ["gpt-4o-mini"] = "o200k_base",
            ["gpt-4.1-mini"] = "o200k_base",
            ["gpt-4.1-nano"] = "o200k_base",
            ["gpt-oss-120b"] = "o200k_harmony",
            ["gpt-4"] = "cl100k_base",
            ["gpt-3.5-turbo"] = "cl100k_base",
            ["gpt-3.5"] = "cl100k_base",
            ["gpt-35-turbo"] = "cl100k_base",
            ["davinci-002"] = "cl100k_base",
            ["babbage-002"] = "cl100k_base",
            ["text-embedding-ada-002"] = "cl100k_base",
            ["text-embedding-3-small"] = "cl100k_base",
            ["text-embedding-3-large"] = "cl100k_base",
            ["text-davinci-003"] = "p50k_base",
            ["text-davinci-002"] = "p50k_base",
            ["text-davinci-001"] = "r50k_base",
            ["text-curie-001"] = "r50k_base",
            ["text-babbage-001"] = "r50k_base",
            ["text-ada-001"] = "r50k_base",
            ["davinci"] = "r50k_base",
            ["curie"] = "r50k_base",
            ["babbage"] = "r50k_base",
            ["ada"] = "r50k_base",
            ["code-davinci-002"] = "p50k_base",
            ["code-davinci-001"] = "p50k_base",
            ["code-cushman-002"] = "p50k_base",
            ["code-cushman-001"] = "p50k_base",
            ["davinci-codex"] = "p50k_base",
            ["cushman-codex"] = "p50k_base",
            ["text-davinci-edit-001"] = "p50k_edit",
            ["code-davinci-edit-001"] = "p50k_edit",
            ["text-similarity-davinci-001"] = "r50k_base",
            ["text-similarity-curie-001"] = "r50k_base",
            ["text-similarity-babbage-001"] = "r50k_base",
            ["text-similarity-ada-001"] = "r50k_base",
            ["text-search-davinci-doc-001"] = "r50k_base",
            ["text-search-curie-doc-001"] = "r50k_base",
            ["text-search-babbage-doc-001"] = "r50k_base",
            ["text-search-ada-doc-001"] = "r50k_base",
            ["code-search-babbage-code-001"] = "r50k_base",
            ["code-search-ada-code-001"] = "r50k_base",
            ["gpt2"] = "gpt2",
            ["gpt-2"] = "r50k_base",
        };

        private static readonly (string Prefix, string Encoding)[] ModelPrefixToEncoding = new[]
        {
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
        };

        /// <summary>
        /// Get the encoding spec for a given encoding name.
        /// </summary>
        public static EncodingSpec GetEncodingSpec(string name)
        {
            if (EncodingSpecs.TryGetValue(name, out var spec))
                return spec;
            var supported = string.Join(", ", ListEncodingNames());
            throw new UnknownEncodingException($"Unknown encoding '{name}'. Supported: {supported}");
        }

        /// <summary>
        /// Map a model name to its encoding name.
        /// </summary>
        public static string ModelToEncoding(string model)
        {
            if (ModelToEncodingMap.TryGetValue(model, out var encoding))
                return encoding;
            foreach (var (prefix, enc) in ModelPrefixToEncoding)
            {
                if (model.StartsWith(prefix, StringComparison.Ordinal))
                    return enc;
            }
            throw new UnknownModelException(
                $"Could not automatically map '{model}' to an encoding. Use GetEncoding(name) to select one explicitly.");
        }

        /// <summary>
        /// List all known encoding names, sorted.
        /// </summary>
        public static IReadOnlyList<string> ListEncodingNames()
        {
            var names = EncodingSpecs.Keys.ToList();
            names.Sort(StringComparer.Ordinal);
            return names;
        }
    }
}
