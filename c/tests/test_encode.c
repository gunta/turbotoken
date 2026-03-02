/**
 * test_encode.c -- Basic tests for the turbotoken C API.
 *
 * This test uses assert() and can run without any test framework.
 * It exercises: version, count, encode, decode, round-trip, and limit check.
 *
 * Note: BPE encode/decode tests require a rank file. If the TURBOTOKEN_RANK_FILE
 * environment variable is not set, BPE tests are skipped.
 */

#include "turbotoken.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *read_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    if (len < 0) { fclose(f); return NULL; }
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = (uint8_t *)malloc((size_t)len);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t)len, f) != (size_t)len) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *out_len = (size_t)len;
    return buf;
}

static void test_version(void) {
    const char *v = turbotoken_version();
    assert(v != NULL);
    assert(strlen(v) > 0);
    printf("  version: %s\n", v);
}

static void test_count(void) {
    const uint8_t *text = (const uint8_t *)"hello";
    ptrdiff_t n = turbotoken_count(text, 5);
    assert(n == 5);
}

static void test_utf8_byte_encode_decode(void) {
    const uint8_t text[] = "abc";
    size_t text_len = 3;

    /* Size query */
    ptrdiff_t n = turbotoken_encode_utf8_bytes(text, text_len, NULL, 0);
    assert(n == 3);

    /* Encode */
    uint32_t tokens[3];
    ptrdiff_t written = turbotoken_encode_utf8_bytes(text, text_len, tokens, 3);
    assert(written == 3);
    assert(tokens[0] == (uint32_t)'a');
    assert(tokens[1] == (uint32_t)'b');
    assert(tokens[2] == (uint32_t)'c');

    /* Decode size query */
    ptrdiff_t dec_n = turbotoken_decode_utf8_bytes(tokens, 3, NULL, 0);
    assert(dec_n == 3);

    /* Decode */
    uint8_t decoded[4] = {0};
    ptrdiff_t dec_written = turbotoken_decode_utf8_bytes(tokens, 3, decoded, 3);
    assert(dec_written == 3);
    assert(memcmp(decoded, text, 3) == 0);
}

static void test_bpe_round_trip(const uint8_t *rank_bytes, size_t rank_len) {
    const char *text = "hello world";
    size_t text_len = strlen(text);

    /* Encode: size query */
    ptrdiff_t n = turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        NULL, 0);
    assert(n > 0);

    /* Encode: fill buffer */
    uint32_t *tokens = (uint32_t *)malloc(sizeof(uint32_t) * (size_t)n);
    assert(tokens != NULL);
    ptrdiff_t written = turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        tokens, (size_t)n);
    assert(written == n);

    /* Count should match */
    ptrdiff_t count = turbotoken_count_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len);
    assert(count == n);

    /* Decode: size query */
    ptrdiff_t dec_n = turbotoken_decode_bpe_from_ranks(
        rank_bytes, rank_len,
        tokens, (size_t)written,
        NULL, 0);
    assert(dec_n > 0);

    /* Decode: fill buffer */
    uint8_t *decoded = (uint8_t *)malloc((size_t)dec_n + 1);
    assert(decoded != NULL);
    ptrdiff_t dec_written = turbotoken_decode_bpe_from_ranks(
        rank_bytes, rank_len,
        tokens, (size_t)written,
        decoded, (size_t)dec_n);
    assert(dec_written == (ptrdiff_t)text_len);
    assert(memcmp(decoded, text, text_len) == 0);

    free(decoded);
    free(tokens);
}

static void test_bpe_limit(const uint8_t *rank_bytes, size_t rank_len) {
    const char *text = "hello world";
    size_t text_len = strlen(text);

    /* Within a large limit */
    ptrdiff_t r = turbotoken_is_within_token_limit_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        100000);
    assert(r >= 0);

    /* Exceed a limit of 1 */
    ptrdiff_t r2 = turbotoken_is_within_token_limit_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        1);
    /* Should be -2 (exceeded) or the count if it's 1 token */
    assert(r2 == -2 || r2 >= 0);
}

static void test_cache_clear(void) {
    /* Should not crash */
    turbotoken_clear_rank_table_cache();
}

int main(void) {
    printf("turbotoken C tests\n");

    printf("test_version...\n");
    test_version();

    printf("test_count...\n");
    test_count();

    printf("test_utf8_byte_encode_decode...\n");
    test_utf8_byte_encode_decode();

    printf("test_cache_clear...\n");
    test_cache_clear();

    /* BPE tests need a rank file */
    const char *rank_path = getenv("TURBOTOKEN_RANK_FILE");
    if (rank_path) {
        size_t rank_len = 0;
        uint8_t *rank_bytes = read_file(rank_path, &rank_len);
        if (rank_bytes) {
            printf("test_bpe_round_trip...\n");
            test_bpe_round_trip(rank_bytes, rank_len);

            printf("test_bpe_limit...\n");
            test_bpe_limit(rank_bytes, rank_len);

            free(rank_bytes);
        } else {
            printf("SKIP: cannot read rank file '%s'\n", rank_path);
        }
    } else {
        printf("SKIP: set TURBOTOKEN_RANK_FILE to enable BPE tests\n");
    }

    printf("All tests passed.\n");
    return 0;
}
