/**
 * chat_example.c -- Encode chat messages using turbotoken.
 *
 * Usage:
 *   ./chat_example <rank-file>
 *
 * Demonstrates encoding chat-style messages by concatenating role/content
 * strings and encoding each segment. This mirrors how chat templates work
 * at the tokenizer level.
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

typedef struct {
    const char *role;
    const char *content;
} ChatMessage;

static ptrdiff_t encode_segment(
    const uint8_t *rank_bytes, size_t rank_len,
    const char *text,
    uint32_t *out_tokens, size_t out_cap)
{
    return turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, strlen(text),
        out_tokens, out_cap);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <rank-file>\n", argv[0]);
        return 1;
    }

    size_t rank_len = 0;
    uint8_t *rank_bytes = read_file(argv[1], &rank_len);
    if (!rank_bytes) {
        fprintf(stderr, "Error: cannot read rank file '%s'\n", argv[1]);
        return 1;
    }

    ChatMessage messages[] = {
        {"system",    "You are a helpful assistant."},
        {"user",      "What is BPE tokenization?"},
        {"assistant", "BPE (Byte Pair Encoding) is a subword tokenization algorithm..."},
    };
    size_t n_messages = sizeof(messages) / sizeof(messages[0]);

    /* Template markers */
    const char *msg_start = "<|im_start|>";
    const char *msg_end = "<|im_end|>\n";

    /* Collect total token count across all segments */
    size_t total_tokens = 0;
    for (size_t i = 0; i < n_messages; i++) {
        /* Build formatted segment: <|im_start|>role\ncontent<|im_end|>\n */
        size_t seg_len = strlen(msg_start) + strlen(messages[i].role) + 1 +
                         strlen(messages[i].content) + strlen(msg_end);
        char *segment = (char *)malloc(seg_len + 1);
        if (!segment) {
            fprintf(stderr, "Error: allocation failed\n");
            free(rank_bytes);
            return 1;
        }
        snprintf(segment, seg_len + 1, "%s%s\n%s%s",
                 msg_start, messages[i].role, messages[i].content, msg_end);

        ptrdiff_t n = encode_segment(rank_bytes, rank_len, segment, NULL, 0);
        if (n < 0) {
            fprintf(stderr, "Error: encode failed for message %zu\n", i);
            free(segment);
            free(rank_bytes);
            return 1;
        }

        printf("[%s] %td tokens\n", messages[i].role, n);
        total_tokens += (size_t)n;
        free(segment);
    }

    printf("Total tokens across %zu messages: %zu\n", n_messages, total_tokens);

    free(rank_bytes);
    return 0;
}
