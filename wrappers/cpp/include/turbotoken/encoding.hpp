#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "turbotoken/chat.hpp"
#include "turbotoken/registry.hpp"

namespace turbotoken {

class Encoding {
public:
    Encoding(const Encoding&) = delete;
    Encoding& operator=(const Encoding&) = delete;
    Encoding(Encoding&&) noexcept = default;
    Encoding& operator=(Encoding&&) noexcept = default;
    ~Encoding() = default;

    static Encoding get(const std::string& name);
    static Encoding for_model(const std::string& model);

    std::vector<uint32_t> encode(std::string_view text) const;
    std::string decode(const std::vector<uint32_t>& tokens) const;
    size_t count(std::string_view text) const;
    size_t count_tokens(std::string_view text) const;
    std::optional<size_t> is_within_token_limit(std::string_view text, size_t limit) const;

    std::vector<uint32_t> encode_chat(
        const std::vector<ChatMessage>& messages,
        const ChatOptions& opts = {}) const;
    size_t count_chat(
        const std::vector<ChatMessage>& messages,
        const ChatOptions& opts = {}) const;
    std::optional<size_t> is_chat_within_token_limit(
        const std::vector<ChatMessage>& messages,
        size_t limit,
        const ChatOptions& opts = {}) const;

    std::vector<uint32_t> encode_file_path(const std::filesystem::path& path) const;
    size_t count_file_path(const std::filesystem::path& path) const;
    std::optional<size_t> is_file_path_within_token_limit(
        const std::filesystem::path& path, size_t limit) const;

    const std::string& name() const { return spec_.name; }
    int n_vocab() const { return spec_.n_vocab; }

private:
    explicit Encoding(std::vector<uint8_t> rank_payload, EncodingSpec spec);

    std::string format_chat(
        const std::vector<ChatMessage>& messages,
        const ChatOptions& opts) const;

    std::vector<uint8_t> rank_payload_;
    EncodingSpec spec_;
};

} // namespace turbotoken
