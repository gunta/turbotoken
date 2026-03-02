#include "turbotoken/encoding.hpp"
#include "turbotoken/error.hpp"
#include "turbotoken/rank_cache.hpp"

#include <turbotoken.h>

#include <fstream>
#include <sstream>

namespace turbotoken {

Encoding::Encoding(std::vector<uint8_t> rank_payload, EncodingSpec spec)
    : rank_payload_(std::move(rank_payload)), spec_(std::move(spec)) {}

Encoding Encoding::get(const std::string& name) {
    auto spec = get_encoding_spec(name);
    auto payload = read_rank_file(name);
    return Encoding(std::move(payload), std::move(spec));
}

Encoding Encoding::for_model(const std::string& model) {
    auto enc_name = model_to_encoding(model);
    return get(enc_name);
}

std::vector<uint32_t> Encoding::encode(std::string_view text) const {
    ptrdiff_t n = turbotoken_encode_bpe_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        reinterpret_cast<const uint8_t*>(text.data()), text.size(),
        nullptr, 0);
    if (n < 0) {
        throw EncodingError("turbotoken_encode_bpe_from_ranks failed");
    }

    std::vector<uint32_t> tokens(static_cast<size_t>(n));
    ptrdiff_t written = turbotoken_encode_bpe_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        reinterpret_cast<const uint8_t*>(text.data()), text.size(),
        tokens.data(), tokens.size());
    if (written < 0) {
        throw EncodingError("turbotoken_encode_bpe_from_ranks failed");
    }
    tokens.resize(static_cast<size_t>(written));
    return tokens;
}

std::string Encoding::decode(const std::vector<uint32_t>& tokens) const {
    ptrdiff_t n = turbotoken_decode_bpe_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        tokens.data(), tokens.size(),
        nullptr, 0);
    if (n < 0) {
        throw DecodingError("turbotoken_decode_bpe_from_ranks failed");
    }

    std::string result(static_cast<size_t>(n), '\0');
    ptrdiff_t written = turbotoken_decode_bpe_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        tokens.data(), tokens.size(),
        reinterpret_cast<uint8_t*>(result.data()), result.size());
    if (written < 0) {
        throw DecodingError("turbotoken_decode_bpe_from_ranks failed");
    }
    result.resize(static_cast<size_t>(written));
    return result;
}

size_t Encoding::count(std::string_view text) const {
    ptrdiff_t n = turbotoken_count_bpe_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        reinterpret_cast<const uint8_t*>(text.data()), text.size());
    if (n < 0) {
        throw EncodingError("turbotoken_count_bpe_from_ranks failed");
    }
    return static_cast<size_t>(n);
}

size_t Encoding::count_tokens(std::string_view text) const {
    return count(text);
}

std::optional<size_t> Encoding::is_within_token_limit(
    std::string_view text, size_t limit) const {
    ptrdiff_t r = turbotoken_is_within_token_limit_bpe_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        reinterpret_cast<const uint8_t*>(text.data()), text.size(),
        limit);
    if (r == -1) {
        throw EncodingError("turbotoken_is_within_token_limit_bpe_from_ranks failed");
    }
    if (r == -2) {
        return std::nullopt;
    }
    return static_cast<size_t>(r);
}

std::string Encoding::format_chat(
    const std::vector<ChatMessage>& messages,
    const ChatOptions& opts) const {
    auto tmpl = resolve_chat_template(opts.mode);
    std::string result;
    for (const auto& msg : messages) {
        result += tmpl.message_prefix;
        result += msg.role;
        result += '\n';
        result += msg.content;
        result += tmpl.message_suffix;
    }
    if (tmpl.assistant_prefix) {
        result += *tmpl.assistant_prefix;
    }
    return result;
}

std::vector<uint32_t> Encoding::encode_chat(
    const std::vector<ChatMessage>& messages,
    const ChatOptions& opts) const {
    return encode(format_chat(messages, opts));
}

size_t Encoding::count_chat(
    const std::vector<ChatMessage>& messages,
    const ChatOptions& opts) const {
    return count(format_chat(messages, opts));
}

std::optional<size_t> Encoding::is_chat_within_token_limit(
    const std::vector<ChatMessage>& messages,
    size_t limit,
    const ChatOptions& opts) const {
    return is_within_token_limit(format_chat(messages, opts), limit);
}

static std::string read_file_contents(const std::filesystem::path& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        throw EncodingError("Cannot open file: " + path.string());
    }
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

std::vector<uint32_t> Encoding::encode_file_path(
    const std::filesystem::path& path) const {
    auto path_str = path.string();
    ptrdiff_t n = turbotoken_encode_bpe_file_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        reinterpret_cast<const uint8_t*>(path_str.data()), path_str.size(),
        nullptr, 0);
    if (n < 0) {
        // Fallback: read file contents and encode directly
        auto contents = read_file_contents(path);
        return encode(contents);
    }

    std::vector<uint32_t> tokens(static_cast<size_t>(n));
    ptrdiff_t written = turbotoken_encode_bpe_file_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        reinterpret_cast<const uint8_t*>(path_str.data()), path_str.size(),
        tokens.data(), tokens.size());
    if (written < 0) {
        throw EncodingError("turbotoken_encode_bpe_file_from_ranks failed");
    }
    tokens.resize(static_cast<size_t>(written));
    return tokens;
}

size_t Encoding::count_file_path(const std::filesystem::path& path) const {
    auto path_str = path.string();
    ptrdiff_t n = turbotoken_count_bpe_file_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        reinterpret_cast<const uint8_t*>(path_str.data()), path_str.size());
    if (n < 0) {
        // Fallback: read file contents and count directly
        auto contents = read_file_contents(path);
        return count(contents);
    }
    return static_cast<size_t>(n);
}

std::optional<size_t> Encoding::is_file_path_within_token_limit(
    const std::filesystem::path& path, size_t limit) const {
    auto path_str = path.string();
    ptrdiff_t r = turbotoken_is_within_token_limit_bpe_file_from_ranks(
        rank_payload_.data(), rank_payload_.size(),
        reinterpret_cast<const uint8_t*>(path_str.data()), path_str.size(),
        limit);
    if (r == -1) {
        // Fallback: read file contents and check limit directly
        auto contents = read_file_contents(path);
        return is_within_token_limit(contents, limit);
    }
    if (r == -2) {
        return std::nullopt;
    }
    return static_cast<size_t>(r);
}

} // namespace turbotoken
