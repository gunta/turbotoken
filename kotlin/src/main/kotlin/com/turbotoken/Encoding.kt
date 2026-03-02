@file:JvmName("KEncoding")
package com.turbotoken

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Kotlin-idiomatic wrapper around the Java Encoding class.
 * Provides extension functions, Result<T> return variants, and suspend variants.
 */
class KEncoding internal constructor(internal val java: Encoding) {

    /** The encoding name. */
    val name: String get() = java.name

    /** The encoding spec. */
    val spec: Registry.EncodingSpec get() = java.spec

    /* ── Core operations ─────────────────────────────────────────────── */

    /** Encodes text into BPE token IDs. */
    fun encode(text: String): IntArray = java.encode(text)

    /** Decodes BPE token IDs back to a string. */
    fun decode(tokens: IntArray): String = java.decode(tokens)

    /** Counts the number of tokens without allocating the token array. */
    fun count(text: String): Int = java.count(text)

    /** Alias for count. */
    fun countTokens(text: String): Int = java.countTokens(text)

    /**
     * Checks if the text is within the given token limit.
     * Returns the token count if within the limit, or null if exceeded.
     */
    fun isWithinTokenLimit(text: String, limit: Int): Int? {
        val opt = java.isWithinTokenLimit(text, limit)
        return if (opt.isPresent) opt.asInt else null
    }

    /* ── Result variants ─────────────────────────────────────────────── */

    /** Encodes text, returning Result to capture exceptions. */
    fun encodeResult(text: String): Result<IntArray> = runCatching { encode(text) }

    /** Decodes tokens, returning Result to capture exceptions. */
    fun decodeResult(tokens: IntArray): Result<String> = runCatching { decode(tokens) }

    /** Counts tokens, returning Result to capture exceptions. */
    fun countResult(text: String): Result<Int> = runCatching { count(text) }

    /* ── Suspend variants ────────────────────────────────────────────── */

    /** Encodes text on the Default dispatcher. */
    suspend fun encodeAsync(text: String): IntArray =
        withContext(Dispatchers.Default) { encode(text) }

    /** Decodes tokens on the Default dispatcher. */
    suspend fun decodeAsync(tokens: IntArray): String =
        withContext(Dispatchers.Default) { decode(tokens) }

    /** Counts tokens on the Default dispatcher. */
    suspend fun countAsync(text: String): Int =
        withContext(Dispatchers.Default) { count(text) }

    /* ── Chat operations ─────────────────────────────────────────────── */

    /** Encodes a list of chat messages into token IDs. */
    fun encodeChat(messages: List<KChatMessage>, options: KChatOptions = KChatOptions()): IntArray {
        val formatted = formatMessages(messages, options)
        return encode(formatted)
    }

    /** Counts tokens in a list of chat messages. */
    fun countChat(messages: List<KChatMessage>, options: KChatOptions = KChatOptions()): Int {
        val formatted = formatMessages(messages, options)
        return count(formatted)
    }

    /** Checks if a chat conversation is within the token limit. */
    fun isChatWithinTokenLimit(messages: List<KChatMessage>, options: KChatOptions = KChatOptions(), limit: Int): Int? {
        val formatted = formatMessages(messages, options)
        return isWithinTokenLimit(formatted, limit)
    }

    /* ── File operations ─────────────────────────────────────────────── */

    /** Encodes a file's contents into BPE token IDs. */
    fun encodeFilePath(filePath: String): IntArray = java.encodeFilePath(filePath)

    /** Counts tokens in a file. */
    fun countFilePath(filePath: String): Int = java.countFilePath(filePath)

    /** Checks if a file is within the token limit. */
    fun isFilePathWithinTokenLimit(filePath: String, limit: Int): Int? {
        val opt = java.isFilePathWithinTokenLimit(filePath, limit)
        return if (opt.isPresent) opt.asInt else null
    }
}

/* ── Extension functions ─────────────────────────────────────────────── */

/**
 * Counts the number of tokens in this string using the given encoding.
 */
fun String.tokenCount(encoding: KEncoding): Int = encoding.count(this)

/**
 * Encodes this string into BPE token IDs using the given encoding.
 */
fun String.encode(encoding: KEncoding): IntArray = encoding.encode(this)
