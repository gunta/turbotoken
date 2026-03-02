#include "turbotoken/registry.hpp"
#include "turbotoken/error.hpp"

#include <algorithm>

namespace turbotoken {

static const char* R50K_PAT_STR =
    R"('(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s)";

static const char* CL100K_PAT_STR =
    R"('(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s)";

static const char* O200K_PAT_STR =
    R"([^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?)"
    R"(|[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?)"
    R"(|\p{N}{1,3})"
    R"(| ?[^\s\p{L}\p{N}]+[\r\n/]*)"
    R"(|\s*[\r\n]+)"
    R"(|\s+(?!\S))"
    R"(|\s+)";

static const std::unordered_map<std::string, EncodingSpec>& get_spec_map() {
    static const auto* specs = new std::unordered_map<std::string, EncodingSpec>{
        {"o200k_base", {
            "o200k_base",
            "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
            O200K_PAT_STR,
            {{"<|endoftext|>", 199999}, {"<|endofprompt|>", 200018}},
            200019
        }},
        {"cl100k_base", {
            "cl100k_base",
            "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
            CL100K_PAT_STR,
            {{"<|endoftext|>", 100257}, {"<|fim_prefix|>", 100258},
             {"<|fim_middle|>", 100259}, {"<|fim_suffix|>", 100260},
             {"<|endofprompt|>", 100276}},
            100277
        }},
        {"p50k_base", {
            "p50k_base",
            "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
            R50K_PAT_STR,
            {{"<|endoftext|>", 50256}},
            50281
        }},
        {"r50k_base", {
            "r50k_base",
            "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
            R50K_PAT_STR,
            {{"<|endoftext|>", 50256}},
            50257
        }},
        {"gpt2", {
            "gpt2",
            "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
            R50K_PAT_STR,
            {{"<|endoftext|>", 50256}},
            50257
        }},
        {"p50k_edit", {
            "p50k_edit",
            "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
            R50K_PAT_STR,
            {{"<|endoftext|>", 50256}},
            50281
        }},
        {"o200k_harmony", {
            "o200k_harmony",
            "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
            O200K_PAT_STR,
            {{"<|endoftext|>", 199999}, {"<|endofprompt|>", 200018}},
            200019
        }},
    };
    return *specs;
}

static const std::unordered_map<std::string, std::string>& get_model_map() {
    static const auto* map = new std::unordered_map<std::string, std::string>{
        {"o1", "o200k_base"},
        {"o3", "o200k_base"},
        {"o4-mini", "o200k_base"},
        {"gpt-5", "o200k_base"},
        {"gpt-4.1", "o200k_base"},
        {"gpt-4o", "o200k_base"},
        {"gpt-4o-mini", "o200k_base"},
        {"gpt-4.1-mini", "o200k_base"},
        {"gpt-4.1-nano", "o200k_base"},
        {"gpt-oss-120b", "o200k_harmony"},
        {"gpt-4", "cl100k_base"},
        {"gpt-3.5-turbo", "cl100k_base"},
        {"gpt-3.5", "cl100k_base"},
        {"gpt-35-turbo", "cl100k_base"},
        {"davinci-002", "cl100k_base"},
        {"babbage-002", "cl100k_base"},
        {"text-embedding-ada-002", "cl100k_base"},
        {"text-embedding-3-small", "cl100k_base"},
        {"text-embedding-3-large", "cl100k_base"},
        {"text-davinci-003", "p50k_base"},
        {"text-davinci-002", "p50k_base"},
        {"text-davinci-001", "r50k_base"},
        {"text-curie-001", "r50k_base"},
        {"text-babbage-001", "r50k_base"},
        {"text-ada-001", "r50k_base"},
        {"davinci", "r50k_base"},
        {"curie", "r50k_base"},
        {"babbage", "r50k_base"},
        {"ada", "r50k_base"},
        {"code-davinci-002", "p50k_base"},
        {"code-davinci-001", "p50k_base"},
        {"code-cushman-002", "p50k_base"},
        {"code-cushman-001", "p50k_base"},
        {"davinci-codex", "p50k_base"},
        {"cushman-codex", "p50k_base"},
        {"text-davinci-edit-001", "p50k_edit"},
        {"code-davinci-edit-001", "p50k_edit"},
        {"text-similarity-davinci-001", "r50k_base"},
        {"text-similarity-curie-001", "r50k_base"},
        {"text-similarity-babbage-001", "r50k_base"},
        {"text-similarity-ada-001", "r50k_base"},
        {"text-search-davinci-doc-001", "r50k_base"},
        {"text-search-curie-doc-001", "r50k_base"},
        {"text-search-babbage-doc-001", "r50k_base"},
        {"text-search-ada-doc-001", "r50k_base"},
        {"code-search-babbage-code-001", "r50k_base"},
        {"code-search-ada-code-001", "r50k_base"},
        {"gpt2", "gpt2"},
        {"gpt-2", "r50k_base"},
    };
    return *map;
}

struct PrefixEntry {
    const char* prefix;
    const char* encoding;
};

static const std::vector<PrefixEntry>& get_prefix_map() {
    static const auto* prefixes = new std::vector<PrefixEntry>{
        {"o1-", "o200k_base"},
        {"o3-", "o200k_base"},
        {"o4-mini-", "o200k_base"},
        {"gpt-5-", "o200k_base"},
        {"gpt-4.5-", "o200k_base"},
        {"gpt-4.1-", "o200k_base"},
        {"chatgpt-4o-", "o200k_base"},
        {"gpt-4o-", "o200k_base"},
        {"gpt-oss-", "o200k_harmony"},
        {"gpt-4-", "cl100k_base"},
        {"gpt-3.5-turbo-", "cl100k_base"},
        {"gpt-35-turbo-", "cl100k_base"},
        {"ft:gpt-4o", "o200k_base"},
        {"ft:gpt-4", "cl100k_base"},
        {"ft:gpt-3.5-turbo", "cl100k_base"},
        {"ft:davinci-002", "cl100k_base"},
        {"ft:babbage-002", "cl100k_base"},
    };
    return *prefixes;
}

const EncodingSpec& get_encoding_spec(const std::string& name) {
    const auto& map = get_spec_map();
    auto it = map.find(name);
    if (it == map.end()) {
        std::string supported;
        for (const auto& [k, v] : map) {
            if (!supported.empty()) supported += ", ";
            supported += k;
        }
        throw InvalidEncodingError(
            "Unknown encoding '" + name + "'. Supported: " + supported);
    }
    return it->second;
}

std::string model_to_encoding(const std::string& model) {
    const auto& map = get_model_map();
    auto it = map.find(model);
    if (it != map.end()) {
        return it->second;
    }

    for (const auto& entry : get_prefix_map()) {
        if (model.rfind(entry.prefix, 0) == 0) {
            return entry.encoding;
        }
    }

    throw InvalidEncodingError(
        "Could not automatically map model '" + model +
        "' to an encoding. Use get(name) to select one explicitly.");
}

std::vector<std::string> list_encoding_names() {
    const auto& map = get_spec_map();
    std::vector<std::string> names;
    names.reserve(map.size());
    for (const auto& [k, v] : map) {
        names.push_back(k);
    }
    std::sort(names.begin(), names.end());
    return names;
}

} // namespace turbotoken
