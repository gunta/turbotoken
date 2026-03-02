/**
 * encoding_test.cpp -- Tests for the turbotoken C++ API.
 *
 * Uses assert() for simplicity (no test framework required).
 *
 * BPE tests require rank files. Set TURBOTOKEN_RANK_FILE to the path of a
 * .tiktoken rank file, or set TURBOTOKEN_CACHE_DIR to a directory containing
 * cached rank files. If neither is set, BPE tests are skipped.
 */

#include "turbotoken/turbotoken.hpp"

#include <turbotoken.h>

#include <cassert>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>

static void test_version() {
    const char* v = turbotoken_version();
    assert(v != nullptr);
    assert(std::strlen(v) > 0);
    std::cout << "  version: " << v << "\n";
}

static void test_registry_list() {
    auto names = turbotoken::list_encoding_names();
    assert(!names.empty());
    std::cout << "  encodings:";
    for (const auto& n : names) {
        std::cout << " " << n;
    }
    std::cout << "\n";

    // Verify sorted
    for (size_t i = 1; i < names.size(); i++) {
        assert(names[i - 1] < names[i]);
    }
}

static void test_registry_specs() {
    auto& spec = turbotoken::get_encoding_spec("cl100k_base");
    assert(spec.name == "cl100k_base");
    assert(spec.n_vocab == 100277);
    assert(!spec.pat_str.empty());
    assert(spec.special_tokens.count("<|endoftext|>") == 1);
    assert(spec.special_tokens.at("<|endoftext|>") == 100257);
}

static void test_model_to_encoding() {
    assert(turbotoken::model_to_encoding("gpt-4o") == "o200k_base");
    assert(turbotoken::model_to_encoding("gpt-4") == "cl100k_base");
    assert(turbotoken::model_to_encoding("gpt-3.5-turbo") == "cl100k_base");
    assert(turbotoken::model_to_encoding("davinci") == "r50k_base");
    assert(turbotoken::model_to_encoding("gpt2") == "gpt2");

    // Prefix matching
    assert(turbotoken::model_to_encoding("gpt-4o-2024-01-01") == "o200k_base");
    assert(turbotoken::model_to_encoding("gpt-4-0613") == "cl100k_base");

    // Unknown model should throw
    bool threw = false;
    try {
        turbotoken::model_to_encoding("nonexistent-model-xyz");
    } catch (const turbotoken::InvalidEncodingError&) {
        threw = true;
    }
    assert(threw);
}

static void test_chat_template() {
    auto tmpl = turbotoken::resolve_chat_template(turbotoken::ChatTemplateMode::im_tokens);
    assert(tmpl.message_prefix == "<|im_start|>");
    assert(tmpl.message_suffix == "<|im_end|>\n");
    assert(!tmpl.assistant_prefix.has_value());

    auto tmpl2 = turbotoken::resolve_chat_template(turbotoken::ChatTemplateMode::turbotoken_v1);
    assert(tmpl2.message_prefix == "<|msg_start|>");
    assert(tmpl2.assistant_prefix.has_value());
}

static void test_invalid_encoding() {
    bool threw = false;
    try {
        turbotoken::get_encoding_spec("nonexistent_encoding");
    } catch (const turbotoken::InvalidEncodingError&) {
        threw = true;
    }
    assert(threw);
}

static void test_encoding_encode_decode(const std::string& rank_file) {
    // Load manually for this test
    auto& spec = turbotoken::get_encoding_spec("cl100k_base");
    (void)spec;

    // We need a rank file loaded. Use read_rank_file with cache.
    // The rank file is already pointed to by the environment.
    auto enc = turbotoken::Encoding::get("cl100k_base");

    std::string text = "hello world";
    auto tokens = enc.encode(text);
    assert(!tokens.empty());
    std::cout << "  encoded \"" << text << "\" -> " << tokens.size() << " tokens\n";

    auto decoded = enc.decode(tokens);
    assert(decoded == text);
    std::cout << "  round-trip: OK\n";
}

static void test_encoding_count(const std::string& rank_file) {
    auto enc = turbotoken::Encoding::get("cl100k_base");
    std::string text = "hello world";
    auto count = enc.count(text);
    assert(count > 0);

    auto tokens = enc.encode(text);
    assert(count == tokens.size());
    std::cout << "  count matches encode: " << count << "\n";
}

static void test_encoding_limit(const std::string& rank_file) {
    auto enc = turbotoken::Encoding::get("cl100k_base");
    std::string text = "hello world";

    auto within = enc.is_within_token_limit(text, 100000);
    assert(within.has_value());
    std::cout << "  within 100000 limit: " << *within << " tokens\n";
}

static void test_encoding_for_model() {
    // This just tests the static factory without needing BPE
    // (would need rank files for actual encoding)
    // We just test that it doesn't throw for known models
    bool threw = false;
    try {
        turbotoken::model_to_encoding("gpt-4o");
    } catch (...) {
        threw = true;
    }
    assert(!threw);
}

int main() {
    std::cout << "turbotoken C++ tests\n";

    std::cout << "test_version...\n";
    test_version();

    std::cout << "test_registry_list...\n";
    test_registry_list();

    std::cout << "test_registry_specs...\n";
    test_registry_specs();

    std::cout << "test_model_to_encoding...\n";
    test_model_to_encoding();

    std::cout << "test_chat_template...\n";
    test_chat_template();

    std::cout << "test_invalid_encoding...\n";
    test_invalid_encoding();

    std::cout << "test_encoding_for_model...\n";
    test_encoding_for_model();

    // BPE tests need cached rank files
    const char* rank_path = std::getenv("TURBOTOKEN_RANK_FILE");
    const char* cache_path = std::getenv("TURBOTOKEN_CACHE_DIR");
    if (rank_path || cache_path) {
        std::string rf = rank_path ? rank_path : "";

        std::cout << "test_encoding_encode_decode...\n";
        test_encoding_encode_decode(rf);

        std::cout << "test_encoding_count...\n";
        test_encoding_count(rf);

        std::cout << "test_encoding_limit...\n";
        test_encoding_limit(rf);
    } else {
        std::cout << "SKIP: set TURBOTOKEN_RANK_FILE or TURBOTOKEN_CACHE_DIR for BPE tests\n";
    }

    std::cout << "All tests passed.\n";
    return 0;
}
