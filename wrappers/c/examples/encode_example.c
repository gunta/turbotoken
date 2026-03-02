/**
 * encode_example.c -- Encode text to BPE tokens, then decode back.
 *
 * Usage:
 *   ./encode_example <path-to-rank-file>
 *
 * Demonstrates the two-pass allocation pattern and round-trip verification.
 */

#include "turbotoken.h"
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

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <rank-file>\n", argv[0]);
        return 1;
    }

    printf("turbotoken version: %s\n", turbotoken_version());

    /* Load rank file */
    size_t rank_len = 0;
    uint8_t *rank_bytes = read_file(argv[1], &rank_len);
    if (!rank_bytes) {
        fprintf(stderr, "Error: cannot read rank file '%s'\n", argv[1]);
        return 1;
    }

    const char *text = "hello world";
    size_t text_len = strlen(text);

    /* Pass 1: query required capacity */
    ptrdiff_t n = turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        NULL, 0);
    if (n < 0) {
        fprintf(stderr, "Error: encode size query failed (%td)\n", n);
        free(rank_bytes);
        return 1;
    }
    printf("Token count for \"%s\": %td\n", text, n);

    /* Pass 2: encode into allocated buffer */
    uint32_t *tokens = (uint32_t *)malloc(sizeof(uint32_t) * (size_t)n);
    if (!tokens) {
        fprintf(stderr, "Error: allocation failed\n");
        free(rank_bytes);
        return 1;
    }
    ptrdiff_t written = turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        tokens, (size_t)n);
    if (written < 0) {
        fprintf(stderr, "Error: encode failed (%td)\n", written);
        free(tokens);
        free(rank_bytes);
        return 1;
    }

    printf("Tokens:");
    for (ptrdiff_t i = 0; i < written; i++) {
        printf(" %u", tokens[i]);
    }
    printf("\n");

    /* Decode back: pass 1 (size query) */
    ptrdiff_t dec_len = turbotoken_decode_bpe_from_ranks(
        rank_bytes, rank_len,
        tokens, (size_t)written,
        NULL, 0);
    if (dec_len < 0) {
        fprintf(stderr, "Error: decode size query failed (%td)\n", dec_len);
        free(tokens);
        free(rank_bytes);
        return 1;
    }

    /* Decode back: pass 2 */
    uint8_t *decoded = (uint8_t *)malloc((size_t)dec_len + 1);
    if (!decoded) {
        fprintf(stderr, "Error: allocation failed\n");
        free(tokens);
        free(rank_bytes);
        return 1;
    }
    ptrdiff_t dec_written = turbotoken_decode_bpe_from_ranks(
        rank_bytes, rank_len,
        tokens, (size_t)written,
        decoded, (size_t)dec_len);
    if (dec_written < 0) {
        fprintf(stderr, "Error: decode failed (%td)\n", dec_written);
        free(decoded);
        free(tokens);
        free(rank_bytes);
        return 1;
    }
    decoded[dec_written] = '\0';
    printf("Decoded: \"%s\"\n", decoded);

    /* Round-trip verification */
    if ((size_t)dec_written == text_len &&
        memcmp(decoded, text, text_len) == 0) {
        printf("Round-trip: OK\n");
    } else {
        fprintf(stderr, "Round-trip: MISMATCH\n");
        free(decoded);
        free(tokens);
        free(rank_bytes);
        return 1;
    }

    free(decoded);
    free(tokens);
    free(rank_bytes);
    return 0;
}
