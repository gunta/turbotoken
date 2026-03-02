#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include "turbotoken.h"

/* ── Version ─────────────────────────────────────────────────────────── */

SEXP C_turbotoken_version(void) {
    const char *v = turbotoken_version();
    return ScalarString(mkChar(v));
}

/* ── Cache management ────────────────────────────────────────────────── */

SEXP C_turbotoken_clear_cache(void) {
    turbotoken_clear_rank_table_cache();
    return R_NilValue;
}

/* ── BPE encode ──────────────────────────────────────────────────────── */

SEXP C_turbotoken_encode_bpe(SEXP rank_raw, SEXP text_str) {
    const uint8_t *rank_bytes = RAW(rank_raw);
    size_t rank_len = (size_t)XLENGTH(rank_raw);
    const char *text = CHAR(STRING_ELT(text_str, 0));
    size_t text_len = strlen(text);

    /* Pass 1: query needed capacity */
    ptrdiff_t n = turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        NULL, 0);
    if (n < 0) {
        Rf_error("turbotoken_encode_bpe failed (error code %td)", n);
    }

    /* Pass 2: fill buffer */
    SEXP result = PROTECT(allocVector(INTSXP, n));
    uint32_t *buf = (uint32_t *)INTEGER(result);
    ptrdiff_t n2 = turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        buf, (size_t)n);
    if (n2 < 0) {
        UNPROTECT(1);
        Rf_error("turbotoken_encode_bpe pass 2 failed (error code %td)", n2);
    }

    /* Shrink if needed */
    if (n2 < n) {
        SEXP trimmed = PROTECT(allocVector(INTSXP, n2));
        memcpy(INTEGER(trimmed), INTEGER(result), (size_t)n2 * sizeof(int));
        UNPROTECT(2);
        return trimmed;
    }

    UNPROTECT(1);
    return result;
}

/* ── BPE decode ──────────────────────────────────────────────────────── */

SEXP C_turbotoken_decode_bpe(SEXP rank_raw, SEXP tokens_int) {
    const uint8_t *rank_bytes = RAW(rank_raw);
    size_t rank_len = (size_t)XLENGTH(rank_raw);
    const uint32_t *tokens = (const uint32_t *)INTEGER(tokens_int);
    size_t token_len = (size_t)XLENGTH(tokens_int);

    /* Pass 1: query needed capacity */
    ptrdiff_t n = turbotoken_decode_bpe_from_ranks(
        rank_bytes, rank_len,
        tokens, token_len,
        NULL, 0);
    if (n < 0) {
        Rf_error("turbotoken_decode_bpe failed (error code %td)", n);
    }

    /* Pass 2: fill buffer */
    uint8_t *buf = (uint8_t *)R_alloc((size_t)n + 1, 1);
    ptrdiff_t n2 = turbotoken_decode_bpe_from_ranks(
        rank_bytes, rank_len,
        tokens, token_len,
        buf, (size_t)n);
    if (n2 < 0) {
        Rf_error("turbotoken_decode_bpe pass 2 failed (error code %td)", n2);
    }
    buf[n2] = '\0';

    SEXP result = PROTECT(allocVector(STRSXP, 1));
    SET_STRING_ELT(result, 0, mkCharLenCE((const char *)buf, (int)n2, CE_UTF8));
    UNPROTECT(1);
    return result;
}

/* ── BPE count ───────────────────────────────────────────────────────── */

SEXP C_turbotoken_count_bpe(SEXP rank_raw, SEXP text_str) {
    const uint8_t *rank_bytes = RAW(rank_raw);
    size_t rank_len = (size_t)XLENGTH(rank_raw);
    const char *text = CHAR(STRING_ELT(text_str, 0));
    size_t text_len = strlen(text);

    ptrdiff_t n = turbotoken_count_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len);
    if (n < 0) {
        Rf_error("turbotoken_count_bpe failed (error code %td)", n);
    }

    return ScalarInteger((int)n);
}

/* ── BPE is within limit ─────────────────────────────────────────────── */

SEXP C_turbotoken_is_within_limit(SEXP rank_raw, SEXP text_str, SEXP limit_int) {
    const uint8_t *rank_bytes = RAW(rank_raw);
    size_t rank_len = (size_t)XLENGTH(rank_raw);
    const char *text = CHAR(STRING_ELT(text_str, 0));
    size_t text_len = strlen(text);
    size_t limit = (size_t)asInteger(limit_int);

    ptrdiff_t n = turbotoken_is_within_token_limit_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, text_len,
        limit);
    if (n == -2) {
        return R_NilValue; /* exceeded limit */
    }
    if (n < 0) {
        Rf_error("turbotoken_is_within_limit failed (error code %td)", n);
    }

    return ScalarInteger((int)n);
}

/* ── BPE file encode ─────────────────────────────────────────────────── */

SEXP C_turbotoken_encode_bpe_file(SEXP rank_raw, SEXP path_str) {
    const uint8_t *rank_bytes = RAW(rank_raw);
    size_t rank_len = (size_t)XLENGTH(rank_raw);
    const char *path = CHAR(STRING_ELT(path_str, 0));
    size_t path_len = strlen(path);

    /* Pass 1: query needed capacity */
    ptrdiff_t n = turbotoken_encode_bpe_file_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)path, path_len,
        NULL, 0);
    if (n < 0) {
        Rf_error("turbotoken_encode_bpe_file failed (error code %td)", n);
    }

    /* Pass 2: fill buffer */
    SEXP result = PROTECT(allocVector(INTSXP, n));
    uint32_t *buf = (uint32_t *)INTEGER(result);
    ptrdiff_t n2 = turbotoken_encode_bpe_file_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)path, path_len,
        buf, (size_t)n);
    if (n2 < 0) {
        UNPROTECT(1);
        Rf_error("turbotoken_encode_bpe_file pass 2 failed (error code %td)", n2);
    }

    if (n2 < n) {
        SEXP trimmed = PROTECT(allocVector(INTSXP, n2));
        memcpy(INTEGER(trimmed), INTEGER(result), (size_t)n2 * sizeof(int));
        UNPROTECT(2);
        return trimmed;
    }

    UNPROTECT(1);
    return result;
}

/* ── BPE file count ──────────────────────────────────────────────────── */

SEXP C_turbotoken_count_bpe_file(SEXP rank_raw, SEXP path_str) {
    const uint8_t *rank_bytes = RAW(rank_raw);
    size_t rank_len = (size_t)XLENGTH(rank_raw);
    const char *path = CHAR(STRING_ELT(path_str, 0));
    size_t path_len = strlen(path);

    ptrdiff_t n = turbotoken_count_bpe_file_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)path, path_len);
    if (n < 0) {
        Rf_error("turbotoken_count_bpe_file failed (error code %td)", n);
    }

    return ScalarInteger((int)n);
}

/* ── BPE file is within limit ────────────────────────────────────────── */

SEXP C_turbotoken_is_within_limit_file(SEXP rank_raw, SEXP path_str, SEXP limit_int) {
    const uint8_t *rank_bytes = RAW(rank_raw);
    size_t rank_len = (size_t)XLENGTH(rank_raw);
    const char *path = CHAR(STRING_ELT(path_str, 0));
    size_t path_len = strlen(path);
    size_t limit = (size_t)asInteger(limit_int);

    ptrdiff_t n = turbotoken_is_within_token_limit_bpe_file_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)path, path_len,
        limit);
    if (n == -2) {
        return R_NilValue;
    }
    if (n < 0) {
        Rf_error("turbotoken_is_within_limit_file failed (error code %td)", n);
    }

    return ScalarInteger((int)n);
}

/* ── Registration table ──────────────────────────────────────────────── */

static const R_CallMethodDef CallEntries[] = {
    {"C_turbotoken_version",          (DL_FUNC) &C_turbotoken_version,          0},
    {"C_turbotoken_clear_cache",      (DL_FUNC) &C_turbotoken_clear_cache,      0},
    {"C_turbotoken_encode_bpe",       (DL_FUNC) &C_turbotoken_encode_bpe,       2},
    {"C_turbotoken_decode_bpe",       (DL_FUNC) &C_turbotoken_decode_bpe,       2},
    {"C_turbotoken_count_bpe",        (DL_FUNC) &C_turbotoken_count_bpe,        2},
    {"C_turbotoken_is_within_limit",  (DL_FUNC) &C_turbotoken_is_within_limit,  3},
    {"C_turbotoken_encode_bpe_file",  (DL_FUNC) &C_turbotoken_encode_bpe_file,  2},
    {"C_turbotoken_count_bpe_file",   (DL_FUNC) &C_turbotoken_count_bpe_file,   2},
    {"C_turbotoken_is_within_limit_file", (DL_FUNC) &C_turbotoken_is_within_limit_file, 3},
    {NULL, NULL, 0}
};

void R_init_turbotoken(DllInfo *dll) {
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
