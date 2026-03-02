/**
 * turbotoken_nif.c — Erlang NIF bridge for Elixir + Gleam bindings.
 *
 * Wraps the turbotoken C ABI with Erlang NIF-compatible signatures.
 * Shared by both elixir/ and gleam/ packages.
 */

#include <erl_nif.h>
#include <string.h>
#include <stdlib.h>
#include "turbotoken.h"

/* ── Helpers ─────────────────────────────────────────────────────────── */

static ERL_NIF_TERM make_error(ErlNifEnv *env, const char *reason) {
    return enif_make_tuple2(env,
        enif_make_atom(env, "error"),
        enif_make_atom(env, reason));
}

static ERL_NIF_TERM make_ok(ErlNifEnv *env, ERL_NIF_TERM value) {
    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        value);
}

/* ── version/0 ───────────────────────────────────────────────────────── */

static ERL_NIF_TERM nif_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc; (void)argv;
    const char *v = turbotoken_version();
    return enif_make_string(env, v, ERL_NIF_LATIN1);
}

/* ── clear_rank_table_cache/0 ────────────────────────────────────────── */

static ERL_NIF_TERM nif_clear_rank_table_cache(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc; (void)argv;
    turbotoken_clear_rank_table_cache();
    return enif_make_atom(env, "ok");
}

/* ── encode_bpe/2 ────────────────────────────────────────────────────── */

static ERL_NIF_TERM nif_encode_bpe(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) return enif_make_badarg(env);

    ErlNifBinary rank_bin, text_bin;
    if (!enif_inspect_binary(env, argv[0], &rank_bin) ||
        !enif_inspect_binary(env, argv[1], &text_bin)) {
        return enif_make_badarg(env);
    }

    /* Two-pass: query size, then fill */
    ptrdiff_t needed = turbotoken_encode_bpe_from_ranks(
        rank_bin.data, rank_bin.size,
        text_bin.data, text_bin.size,
        NULL, 0);

    if (needed < 0) {
        return make_error(env, "encode_failed");
    }

    uint32_t *buf = (uint32_t *)enif_alloc((size_t)needed * sizeof(uint32_t));
    if (buf == NULL && needed > 0) {
        return make_error(env, "out_of_memory");
    }

    ptrdiff_t written = turbotoken_encode_bpe_from_ranks(
        rank_bin.data, rank_bin.size,
        text_bin.data, text_bin.size,
        buf, (size_t)needed);

    if (written < 0) {
        enif_free(buf);
        return make_error(env, "encode_failed");
    }

    /* Build Erlang list of integers */
    ERL_NIF_TERM list = enif_make_list(env, 0);
    for (ptrdiff_t i = written - 1; i >= 0; i--) {
        list = enif_make_list_cell(env, enif_make_uint(env, buf[i]), list);
    }

    enif_free(buf);
    return make_ok(env, list);
}

/* ── decode_bpe/2 ────────────────────────────────────────────────────── */

static ERL_NIF_TERM nif_decode_bpe(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) return enif_make_badarg(env);

    ErlNifBinary rank_bin;
    if (!enif_inspect_binary(env, argv[0], &rank_bin)) {
        return enif_make_badarg(env);
    }

    /* Convert Erlang list to C array */
    unsigned list_len;
    if (!enif_get_list_length(env, argv[1], &list_len)) {
        return enif_make_badarg(env);
    }

    uint32_t *tokens = (uint32_t *)enif_alloc(list_len * sizeof(uint32_t));
    if (tokens == NULL && list_len > 0) {
        return make_error(env, "out_of_memory");
    }

    ERL_NIF_TERM head, tail = argv[1];
    for (unsigned i = 0; i < list_len; i++) {
        if (!enif_get_list_cell(env, tail, &head, &tail)) {
            enif_free(tokens);
            return enif_make_badarg(env);
        }
        unsigned val;
        if (!enif_get_uint(env, head, &val)) {
            enif_free(tokens);
            return enif_make_badarg(env);
        }
        tokens[i] = (uint32_t)val;
    }

    /* Two-pass */
    ptrdiff_t needed = turbotoken_decode_bpe_from_ranks(
        rank_bin.data, rank_bin.size,
        tokens, list_len,
        NULL, 0);

    if (needed < 0) {
        enif_free(tokens);
        return make_error(env, "decode_failed");
    }

    ErlNifBinary out_bin;
    if (!enif_alloc_binary((size_t)needed, &out_bin)) {
        enif_free(tokens);
        return make_error(env, "out_of_memory");
    }

    ptrdiff_t written = turbotoken_decode_bpe_from_ranks(
        rank_bin.data, rank_bin.size,
        tokens, list_len,
        out_bin.data, (size_t)needed);

    enif_free(tokens);

    if (written < 0) {
        enif_release_binary(&out_bin);
        return make_error(env, "decode_failed");
    }

    return make_ok(env, enif_make_binary(env, &out_bin));
}

/* ── count_bpe/2 ─────────────────────────────────────────────────────── */

static ERL_NIF_TERM nif_count_bpe(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) return enif_make_badarg(env);

    ErlNifBinary rank_bin, text_bin;
    if (!enif_inspect_binary(env, argv[0], &rank_bin) ||
        !enif_inspect_binary(env, argv[1], &text_bin)) {
        return enif_make_badarg(env);
    }

    ptrdiff_t count = turbotoken_count_bpe_from_ranks(
        rank_bin.data, rank_bin.size,
        text_bin.data, text_bin.size);

    if (count < 0) {
        return make_error(env, "count_failed");
    }

    return make_ok(env, enif_make_long(env, (long)count));
}

/* ── is_within_token_limit/3 ─────────────────────────────────────────── */

static ERL_NIF_TERM nif_is_within_token_limit(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 3) return enif_make_badarg(env);

    ErlNifBinary rank_bin, text_bin;
    unsigned long limit;
    if (!enif_inspect_binary(env, argv[0], &rank_bin) ||
        !enif_inspect_binary(env, argv[1], &text_bin) ||
        !enif_get_ulong(env, argv[2], &limit)) {
        return enif_make_badarg(env);
    }

    ptrdiff_t result = turbotoken_is_within_token_limit_bpe_from_ranks(
        rank_bin.data, rank_bin.size,
        text_bin.data, text_bin.size,
        (size_t)limit);

    if (result == -1) {
        return make_error(env, "check_failed");
    }
    if (result == -2) {
        return make_ok(env, enif_make_atom(env, "false"));
    }

    return make_ok(env, enif_make_long(env, (long)result));
}

/* ── count_bpe_file/2 ────────────────────────────────────────────────── */

static ERL_NIF_TERM nif_count_bpe_file(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) return enif_make_badarg(env);

    ErlNifBinary rank_bin, path_bin;
    if (!enif_inspect_binary(env, argv[0], &rank_bin) ||
        !enif_inspect_binary(env, argv[1], &path_bin)) {
        return enif_make_badarg(env);
    }

    ptrdiff_t count = turbotoken_count_bpe_file_from_ranks(
        rank_bin.data, rank_bin.size,
        path_bin.data, path_bin.size);

    if (count < 0) {
        return make_error(env, "file_count_failed");
    }

    return make_ok(env, enif_make_long(env, (long)count));
}

/* ── train_bpe_from_chunk_counts/5 ───────────────────────────────────── */

static ERL_NIF_TERM nif_train_bpe(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 5) return enif_make_badarg(env);

    ErlNifBinary chunks_bin;
    if (!enif_inspect_binary(env, argv[0], &chunks_bin)) {
        return enif_make_badarg(env);
    }

    /* Offsets and counts as lists */
    unsigned offsets_len, counts_len;
    if (!enif_get_list_length(env, argv[1], &offsets_len) ||
        !enif_get_list_length(env, argv[2], &counts_len)) {
        return enif_make_badarg(env);
    }

    uint32_t *offsets = (uint32_t *)enif_alloc(offsets_len * sizeof(uint32_t));
    uint32_t *counts = (uint32_t *)enif_alloc(counts_len * sizeof(uint32_t));
    if ((offsets == NULL && offsets_len > 0) || (counts == NULL && counts_len > 0)) {
        if (offsets) enif_free(offsets);
        if (counts) enif_free(counts);
        return make_error(env, "out_of_memory");
    }

    ERL_NIF_TERM head, tail;
    tail = argv[1];
    for (unsigned i = 0; i < offsets_len; i++) {
        enif_get_list_cell(env, tail, &head, &tail);
        unsigned val;
        enif_get_uint(env, head, &val);
        offsets[i] = val;
    }
    tail = argv[2];
    for (unsigned i = 0; i < counts_len; i++) {
        enif_get_list_cell(env, tail, &head, &tail);
        unsigned val;
        enif_get_uint(env, head, &val);
        counts[i] = val;
    }

    unsigned vocab_size, min_freq;
    if (!enif_get_uint(env, argv[3], &vocab_size) ||
        !enif_get_uint(env, argv[4], &min_freq)) {
        enif_free(offsets);
        enif_free(counts);
        return enif_make_badarg(env);
    }

    ptrdiff_t needed = turbotoken_train_bpe_from_chunk_counts(
        chunks_bin.data, chunks_bin.size,
        offsets, offsets_len, counts, counts_len,
        vocab_size, min_freq, NULL, 0);

    if (needed < 0) {
        enif_free(offsets);
        enif_free(counts);
        return make_error(env, "train_failed");
    }

    uint32_t *merges = (uint32_t *)enif_alloc((size_t)needed * sizeof(uint32_t));
    if (merges == NULL && needed > 0) {
        enif_free(offsets);
        enif_free(counts);
        return make_error(env, "out_of_memory");
    }

    ptrdiff_t written = turbotoken_train_bpe_from_chunk_counts(
        chunks_bin.data, chunks_bin.size,
        offsets, offsets_len, counts, counts_len,
        vocab_size, min_freq, merges, (size_t)needed);

    enif_free(offsets);
    enif_free(counts);

    if (written < 0) {
        enif_free(merges);
        return make_error(env, "train_failed");
    }

    ERL_NIF_TERM list = enif_make_list(env, 0);
    for (ptrdiff_t i = written - 1; i >= 0; i--) {
        list = enif_make_list_cell(env, enif_make_uint(env, merges[i]), list);
    }

    enif_free(merges);
    return make_ok(env, list);
}

/* ── NIF function table ──────────────────────────────────────────────── */

static ErlNifFunc nif_funcs[] = {
    {"version",                  0, nif_version,                0},
    {"clear_rank_table_cache",   0, nif_clear_rank_table_cache, 0},
    {"encode_bpe",               2, nif_encode_bpe,             0},
    {"decode_bpe",               2, nif_decode_bpe,             0},
    {"count_bpe",                2, nif_count_bpe,              0},
    {"is_within_token_limit",    3, nif_is_within_token_limit,  0},
    {"count_bpe_file",           2, nif_count_bpe_file,         0},
    {"train_bpe",                5, nif_train_bpe,              0},
};

ERL_NIF_INIT(Elixir.TurboToken.Nif, nif_funcs, NULL, NULL, NULL, NULL)
