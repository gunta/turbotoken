#include <stdint.h>
#include <stddef.h>

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#else
#define EMSCRIPTEN_KEEPALIVE
#endif

EMSCRIPTEN_KEEPALIVE
int32_t tt_encode_utf8_bytes(
    const uint8_t *text,
    size_t text_len,
    uint32_t *out_tokens,
    size_t out_cap
) {
    if (out_tokens == NULL) {
        if (text_len > (size_t)INT32_MAX) {
            return -1;
        }
        return (int32_t)text_len;
    }
    if (text == NULL && text_len > 0) {
        return -1;
    }
    if (out_cap < text_len) {
        return -1;
    }
    for (size_t i = 0; i < text_len; i += 1) {
        out_tokens[i] = (uint32_t)text[i];
    }
    if (text_len > (size_t)INT32_MAX) {
        return -1;
    }
    return (int32_t)text_len;
}

EMSCRIPTEN_KEEPALIVE
int32_t tt_decode_utf8_bytes(
    const uint32_t *tokens,
    size_t token_len,
    uint8_t *out_bytes,
    size_t out_cap
) {
    if (out_bytes == NULL) {
        if (token_len > (size_t)INT32_MAX) {
            return -1;
        }
        return (int32_t)token_len;
    }
    if (tokens == NULL && token_len > 0) {
        return -1;
    }
    if (out_cap < token_len) {
        return -1;
    }
    for (size_t i = 0; i < token_len; i += 1) {
        if (tokens[i] > 255U) {
            return -1;
        }
        out_bytes[i] = (uint8_t)tokens[i];
    }
    if (token_len > (size_t)INT32_MAX) {
        return -1;
    }
    return (int32_t)token_len;
}
