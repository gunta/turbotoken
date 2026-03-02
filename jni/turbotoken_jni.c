/**
 * turbotoken_jni.c — JNI bridge for Java + Kotlin bindings.
 *
 * Wraps the turbotoken C ABI with JNI-compatible signatures.
 * Shared by both java/ and kotlin/ packages.
 */

#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include "turbotoken.h"

/* ── Helpers ─────────────────────────────────────────────────────────── */

static void throw_turbotoken_exception(JNIEnv *env, const char *msg) {
    jclass cls = (*env)->FindClass(env, "com/turbotoken/TurboTokenException");
    if (cls != NULL) {
        (*env)->ThrowNew(env, cls, msg);
    }
}

/* ── Version ─────────────────────────────────────────────────────────── */

JNIEXPORT jstring JNICALL
Java_com_turbotoken_NativeBridge_version(JNIEnv *env, jclass cls) {
    (void)cls;
    const char *v = turbotoken_version();
    return (*env)->NewStringUTF(env, v);
}

/* ── Cache management ────────────────────────────────────────────────── */

JNIEXPORT void JNICALL
Java_com_turbotoken_NativeBridge_clearRankTableCache(JNIEnv *env, jclass cls) {
    (void)env;
    (void)cls;
    turbotoken_clear_rank_table_cache();
}

/* ── BPE encode ──────────────────────────────────────────────────────── */

JNIEXPORT jintArray JNICALL
Java_com_turbotoken_NativeBridge_encodeBpe(
    JNIEnv *env, jclass cls,
    jbyteArray rankBytes, jbyteArray textBytes)
{
    (void)cls;

    jsize rank_len = (*env)->GetArrayLength(env, rankBytes);
    jsize text_len = (*env)->GetArrayLength(env, textBytes);

    jbyte *rank_ptr = (*env)->GetByteArrayElements(env, rankBytes, NULL);
    jbyte *text_ptr = (*env)->GetByteArrayElements(env, textBytes, NULL);

    if (rank_ptr == NULL || text_ptr == NULL) {
        if (rank_ptr) (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        if (text_ptr) (*env)->ReleaseByteArrayElements(env, textBytes, text_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "failed to pin byte arrays");
        return NULL;
    }

    /* Two-pass: query size, then fill */
    ptrdiff_t needed = turbotoken_encode_bpe_from_ranks(
        (const uint8_t *)rank_ptr, (size_t)rank_len,
        (const uint8_t *)text_ptr, (size_t)text_len,
        NULL, 0);

    if (needed < 0) {
        (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        (*env)->ReleaseByteArrayElements(env, textBytes, text_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "encode failed (pass 1)");
        return NULL;
    }

    uint32_t *buf = (uint32_t *)malloc((size_t)needed * sizeof(uint32_t));
    if (buf == NULL && needed > 0) {
        (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        (*env)->ReleaseByteArrayElements(env, textBytes, text_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "out of memory");
        return NULL;
    }

    ptrdiff_t written = turbotoken_encode_bpe_from_ranks(
        (const uint8_t *)rank_ptr, (size_t)rank_len,
        (const uint8_t *)text_ptr, (size_t)text_len,
        buf, (size_t)needed);

    (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, textBytes, text_ptr, JNI_ABORT);

    if (written < 0) {
        free(buf);
        throw_turbotoken_exception(env, "encode failed (pass 2)");
        return NULL;
    }

    jintArray result = (*env)->NewIntArray(env, (jsize)written);
    if (result != NULL && written > 0) {
        (*env)->SetIntArrayRegion(env, result, 0, (jsize)written, (const jint *)buf);
    }

    free(buf);
    return result;
}

/* ── BPE decode ──────────────────────────────────────────────────────── */

JNIEXPORT jbyteArray JNICALL
Java_com_turbotoken_NativeBridge_decodeBpe(
    JNIEnv *env, jclass cls,
    jbyteArray rankBytes, jintArray tokenArray)
{
    (void)cls;

    jsize rank_len = (*env)->GetArrayLength(env, rankBytes);
    jsize token_len = (*env)->GetArrayLength(env, tokenArray);

    jbyte *rank_ptr = (*env)->GetByteArrayElements(env, rankBytes, NULL);
    jint *token_ptr = (*env)->GetIntArrayElements(env, tokenArray, NULL);

    if (rank_ptr == NULL || token_ptr == NULL) {
        if (rank_ptr) (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        if (token_ptr) (*env)->ReleaseIntArrayElements(env, tokenArray, token_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "failed to pin arrays");
        return NULL;
    }

    /* Two-pass */
    ptrdiff_t needed = turbotoken_decode_bpe_from_ranks(
        (const uint8_t *)rank_ptr, (size_t)rank_len,
        (const uint32_t *)token_ptr, (size_t)token_len,
        NULL, 0);

    if (needed < 0) {
        (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        (*env)->ReleaseIntArrayElements(env, tokenArray, token_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "decode failed (pass 1)");
        return NULL;
    }

    uint8_t *buf = (uint8_t *)malloc((size_t)needed);
    if (buf == NULL && needed > 0) {
        (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        (*env)->ReleaseIntArrayElements(env, tokenArray, token_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "out of memory");
        return NULL;
    }

    ptrdiff_t written = turbotoken_decode_bpe_from_ranks(
        (const uint8_t *)rank_ptr, (size_t)rank_len,
        (const uint32_t *)token_ptr, (size_t)token_len,
        buf, (size_t)needed);

    (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
    (*env)->ReleaseIntArrayElements(env, tokenArray, token_ptr, JNI_ABORT);

    if (written < 0) {
        free(buf);
        throw_turbotoken_exception(env, "decode failed (pass 2)");
        return NULL;
    }

    jbyteArray result = (*env)->NewByteArray(env, (jsize)written);
    if (result != NULL && written > 0) {
        (*env)->SetByteArrayRegion(env, result, 0, (jsize)written, (const jbyte *)buf);
    }

    free(buf);
    return result;
}

/* ── BPE count ───────────────────────────────────────────────────────── */

JNIEXPORT jlong JNICALL
Java_com_turbotoken_NativeBridge_countBpe(
    JNIEnv *env, jclass cls,
    jbyteArray rankBytes, jbyteArray textBytes)
{
    (void)cls;

    jsize rank_len = (*env)->GetArrayLength(env, rankBytes);
    jsize text_len = (*env)->GetArrayLength(env, textBytes);

    jbyte *rank_ptr = (*env)->GetByteArrayElements(env, rankBytes, NULL);
    jbyte *text_ptr = (*env)->GetByteArrayElements(env, textBytes, NULL);

    if (rank_ptr == NULL || text_ptr == NULL) {
        if (rank_ptr) (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        if (text_ptr) (*env)->ReleaseByteArrayElements(env, textBytes, text_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "failed to pin byte arrays");
        return -1;
    }

    ptrdiff_t count = turbotoken_count_bpe_from_ranks(
        (const uint8_t *)rank_ptr, (size_t)rank_len,
        (const uint8_t *)text_ptr, (size_t)text_len);

    (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, textBytes, text_ptr, JNI_ABORT);

    if (count < 0) {
        throw_turbotoken_exception(env, "count failed");
        return -1;
    }

    return (jlong)count;
}

/* ── isWithinTokenLimit ──────────────────────────────────────────────── */

JNIEXPORT jlong JNICALL
Java_com_turbotoken_NativeBridge_isWithinTokenLimit(
    JNIEnv *env, jclass cls,
    jbyteArray rankBytes, jbyteArray textBytes, jlong tokenLimit)
{
    (void)cls;

    jsize rank_len = (*env)->GetArrayLength(env, rankBytes);
    jsize text_len = (*env)->GetArrayLength(env, textBytes);

    jbyte *rank_ptr = (*env)->GetByteArrayElements(env, rankBytes, NULL);
    jbyte *text_ptr = (*env)->GetByteArrayElements(env, textBytes, NULL);

    if (rank_ptr == NULL || text_ptr == NULL) {
        if (rank_ptr) (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        if (text_ptr) (*env)->ReleaseByteArrayElements(env, textBytes, text_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "failed to pin byte arrays");
        return -1;
    }

    ptrdiff_t result = turbotoken_is_within_token_limit_bpe_from_ranks(
        (const uint8_t *)rank_ptr, (size_t)rank_len,
        (const uint8_t *)text_ptr, (size_t)text_len,
        (size_t)tokenLimit);

    (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, textBytes, text_ptr, JNI_ABORT);

    if (result == -1) {
        throw_turbotoken_exception(env, "isWithinTokenLimit failed");
        return -1;
    }

    /* -2 = limit exceeded, >= 0 = token count */
    return (jlong)result;
}

/* ── BPE file encode ─────────────────────────────────────────────────── */

JNIEXPORT jintArray JNICALL
Java_com_turbotoken_NativeBridge_encodeBpeFile(
    JNIEnv *env, jclass cls,
    jbyteArray rankBytes, jstring filePath)
{
    (void)cls;

    jsize rank_len = (*env)->GetArrayLength(env, rankBytes);
    jbyte *rank_ptr = (*env)->GetByteArrayElements(env, rankBytes, NULL);
    const char *path_str = (*env)->GetStringUTFChars(env, filePath, NULL);

    if (rank_ptr == NULL || path_str == NULL) {
        if (rank_ptr) (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        if (path_str) (*env)->ReleaseStringUTFChars(env, filePath, path_str);
        throw_turbotoken_exception(env, "failed to pin arrays");
        return NULL;
    }

    size_t path_len = strlen(path_str);

    ptrdiff_t needed = turbotoken_encode_bpe_file_from_ranks(
        (const uint8_t *)rank_ptr, (size_t)rank_len,
        (const uint8_t *)path_str, path_len,
        NULL, 0);

    if (needed < 0) {
        (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        (*env)->ReleaseStringUTFChars(env, filePath, path_str);
        throw_turbotoken_exception(env, "file encode failed (pass 1)");
        return NULL;
    }

    uint32_t *buf = (uint32_t *)malloc((size_t)needed * sizeof(uint32_t));
    if (buf == NULL && needed > 0) {
        (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        (*env)->ReleaseStringUTFChars(env, filePath, path_str);
        throw_turbotoken_exception(env, "out of memory");
        return NULL;
    }

    ptrdiff_t written = turbotoken_encode_bpe_file_from_ranks(
        (const uint8_t *)rank_ptr, (size_t)rank_len,
        (const uint8_t *)path_str, path_len,
        buf, (size_t)needed);

    (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
    (*env)->ReleaseStringUTFChars(env, filePath, path_str);

    if (written < 0) {
        free(buf);
        throw_turbotoken_exception(env, "file encode failed (pass 2)");
        return NULL;
    }

    jintArray result = (*env)->NewIntArray(env, (jsize)written);
    if (result != NULL && written > 0) {
        (*env)->SetIntArrayRegion(env, result, 0, (jsize)written, (const jint *)buf);
    }

    free(buf);
    return result;
}

/* ── BPE file count ──────────────────────────────────────────────────── */

JNIEXPORT jlong JNICALL
Java_com_turbotoken_NativeBridge_countBpeFile(
    JNIEnv *env, jclass cls,
    jbyteArray rankBytes, jstring filePath)
{
    (void)cls;

    jsize rank_len = (*env)->GetArrayLength(env, rankBytes);
    jbyte *rank_ptr = (*env)->GetByteArrayElements(env, rankBytes, NULL);
    const char *path_str = (*env)->GetStringUTFChars(env, filePath, NULL);

    if (rank_ptr == NULL || path_str == NULL) {
        if (rank_ptr) (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
        if (path_str) (*env)->ReleaseStringUTFChars(env, filePath, path_str);
        throw_turbotoken_exception(env, "failed to pin arrays");
        return -1;
    }

    ptrdiff_t count = turbotoken_count_bpe_file_from_ranks(
        (const uint8_t *)rank_ptr, (size_t)rank_len,
        (const uint8_t *)path_str, strlen(path_str));

    (*env)->ReleaseByteArrayElements(env, rankBytes, rank_ptr, JNI_ABORT);
    (*env)->ReleaseStringUTFChars(env, filePath, path_str);

    if (count < 0) {
        throw_turbotoken_exception(env, "file count failed");
        return -1;
    }

    return (jlong)count;
}

/* ── Training ────────────────────────────────────────────────────────── */

JNIEXPORT jintArray JNICALL
Java_com_turbotoken_NativeBridge_trainBpeFromChunkCounts(
    JNIEnv *env, jclass cls,
    jbyteArray chunks, jintArray chunkOffsets, jintArray chunkCounts,
    jint vocabSize, jint minFrequency)
{
    (void)cls;

    jsize chunks_len = (*env)->GetArrayLength(env, chunks);
    jsize offsets_len = (*env)->GetArrayLength(env, chunkOffsets);
    jsize counts_len = (*env)->GetArrayLength(env, chunkCounts);

    jbyte *chunks_ptr = (*env)->GetByteArrayElements(env, chunks, NULL);
    jint *offsets_ptr = (*env)->GetIntArrayElements(env, chunkOffsets, NULL);
    jint *counts_ptr = (*env)->GetIntArrayElements(env, chunkCounts, NULL);

    if (chunks_ptr == NULL || offsets_ptr == NULL || counts_ptr == NULL) {
        if (chunks_ptr) (*env)->ReleaseByteArrayElements(env, chunks, chunks_ptr, JNI_ABORT);
        if (offsets_ptr) (*env)->ReleaseIntArrayElements(env, chunkOffsets, offsets_ptr, JNI_ABORT);
        if (counts_ptr) (*env)->ReleaseIntArrayElements(env, chunkCounts, counts_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "failed to pin arrays");
        return NULL;
    }

    ptrdiff_t needed = turbotoken_train_bpe_from_chunk_counts(
        (const uint8_t *)chunks_ptr, (size_t)chunks_len,
        (const uint32_t *)offsets_ptr, (size_t)offsets_len,
        (const uint32_t *)counts_ptr, (size_t)counts_len,
        (uint32_t)vocabSize, (uint32_t)minFrequency,
        NULL, 0);

    if (needed < 0) {
        (*env)->ReleaseByteArrayElements(env, chunks, chunks_ptr, JNI_ABORT);
        (*env)->ReleaseIntArrayElements(env, chunkOffsets, offsets_ptr, JNI_ABORT);
        (*env)->ReleaseIntArrayElements(env, chunkCounts, counts_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "training failed (pass 1)");
        return NULL;
    }

    uint32_t *buf = (uint32_t *)malloc((size_t)needed * sizeof(uint32_t));
    if (buf == NULL && needed > 0) {
        (*env)->ReleaseByteArrayElements(env, chunks, chunks_ptr, JNI_ABORT);
        (*env)->ReleaseIntArrayElements(env, chunkOffsets, offsets_ptr, JNI_ABORT);
        (*env)->ReleaseIntArrayElements(env, chunkCounts, counts_ptr, JNI_ABORT);
        throw_turbotoken_exception(env, "out of memory");
        return NULL;
    }

    ptrdiff_t written = turbotoken_train_bpe_from_chunk_counts(
        (const uint8_t *)chunks_ptr, (size_t)chunks_len,
        (const uint32_t *)offsets_ptr, (size_t)offsets_len,
        (const uint32_t *)counts_ptr, (size_t)counts_len,
        (uint32_t)vocabSize, (uint32_t)minFrequency,
        buf, (size_t)needed);

    (*env)->ReleaseByteArrayElements(env, chunks, chunks_ptr, JNI_ABORT);
    (*env)->ReleaseIntArrayElements(env, chunkOffsets, offsets_ptr, JNI_ABORT);
    (*env)->ReleaseIntArrayElements(env, chunkCounts, counts_ptr, JNI_ABORT);

    if (written < 0) {
        free(buf);
        throw_turbotoken_exception(env, "training failed (pass 2)");
        return NULL;
    }

    jintArray result = (*env)->NewIntArray(env, (jsize)written);
    if (result != NULL && written > 0) {
        (*env)->SetIntArrayRegion(env, result, 0, (jsize)written, (const jint *)buf);
    }

    free(buf);
    return result;
}
