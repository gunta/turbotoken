/**
 * count_example.c -- Count BPE tokens in text.
 *
 * Usage:
 *   ./count_example <rank-file> "text to count"
 *   echo "text from stdin" | ./count_example <rank-file>
 *
 * Demonstrates count and is_within_token_limit usage.
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

static char *read_stdin(size_t *out_len) {
    size_t cap = 4096, len = 0;
    char *buf = (char *)malloc(cap);
    if (!buf) return NULL;
    while (!feof(stdin)) {
        size_t n = fread(buf + len, 1, cap - len, stdin);
        len += n;
        if (len == cap) {
            cap *= 2;
            char *tmp = (char *)realloc(buf, cap);
            if (!tmp) { free(buf); return NULL; }
            buf = tmp;
        }
    }
    *out_len = len;
    return buf;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <rank-file> [text]\n", argv[0]);
        return 1;
    }

    size_t rank_len = 0;
    uint8_t *rank_bytes = read_file(argv[1], &rank_len);
    if (!rank_bytes) {
        fprintf(stderr, "Error: cannot read rank file '%s'\n", argv[1]);
        return 1;
    }

    const char *text;
    size_t text_len;
    char *stdin_buf = NULL;

    if (argc >= 3) {
        text = argv[2];
        text_len = strlen(argv[2]);
    } else {
        stdin_buf = read_stdin(&text_len);
        if (!stdin_buf) {
            fprintf(stderr, "Error: failed to read stdin\n");
            free(rank_bytes);
            return 1;
        }
        text = stdin_buf;
    }

    /* Count tokens */
    ptrdiff_t count = turbotoken_count_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len);
    if (count < 0) {
        fprintf(stderr, "Error: count failed (%td)\n", count);
        free(stdin_buf);
        free(rank_bytes);
        return 1;
    }
    printf("Token count: %td\n", count);

    /* Check against a limit of 4096 */
    size_t limit = 4096;
    ptrdiff_t result = turbotoken_is_within_token_limit_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        limit);
    if (result == -2) {
        printf("Exceeds %zu token limit\n", limit);
    } else if (result >= 0) {
        printf("Within %zu token limit (%td tokens)\n", limit, result);
    } else {
        fprintf(stderr, "Error: limit check failed (%td)\n", result);
    }

    free(stdin_buf);
    free(rank_bytes);
    return 0;
}
