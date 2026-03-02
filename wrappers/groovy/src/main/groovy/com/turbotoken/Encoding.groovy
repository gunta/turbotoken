package com.turbotoken

/**
 * A loaded BPE encoding. Thread-safe after construction.
 *
 * Wraps the Java com.turbotoken.Encoding with Groovy-idiomatic features.
 *
 * Use {@link TurboToken#getEncoding} or {@link TurboToken#getEncodingForModel} to obtain instances.
 */
class Encoding {

    private final com.turbotoken.Encoding javaEncoding

    Encoding(com.turbotoken.Encoding javaEncoding) {
        this.javaEncoding = javaEncoding
    }

    /** Returns the encoding name. */
    String getName() { javaEncoding.name }

    /* ── Core operations ─────────────────────────────────────────── */

    /**
     * Encodes text into BPE token IDs.
     */
    List<Integer> encode(String text) {
        javaEncoding.encode(text).toList()
    }

    /**
     * Decodes BPE token IDs back to a string.
     */
    String decode(List<Integer> tokens) {
        javaEncoding.decode(tokens as int[])
    }

    /**
     * Counts the number of tokens in the given text.
     */
    int count(String text) {
        javaEncoding.count(text)
    }

    /**
     * Alias for {@link #count}.
     */
    int countTokens(String text) { count(text) }

    /**
     * Checks if the text is within the given token limit.
     * Returns the token count if within the limit, or null if exceeded.
     */
    Integer isWithinTokenLimit(String text, int limit) {
        def result = javaEncoding.isWithinTokenLimit(text, limit)
        result.present ? result.asInt : null
    }

    /* ── Chat operations ─────────────────────────────────────────── */

    /**
     * Encodes a list of chat messages into token IDs.
     */
    List<Integer> encodeChat(List<Chat.ChatMessage> messages,
                             Chat.ChatOptions options = new Chat.ChatOptions()) {
        def formatted = Chat.formatMessages(messages, options)
        encode(formatted)
    }

    /**
     * Counts tokens in a list of chat messages.
     */
    int countChat(List<Chat.ChatMessage> messages,
                  Chat.ChatOptions options = new Chat.ChatOptions()) {
        def formatted = Chat.formatMessages(messages, options)
        count(formatted)
    }

    /**
     * Checks if a chat conversation is within the token limit.
     */
    Integer isChatWithinTokenLimit(List<Chat.ChatMessage> messages, int limit,
                                   Chat.ChatOptions options = new Chat.ChatOptions()) {
        def formatted = Chat.formatMessages(messages, options)
        isWithinTokenLimit(formatted, limit)
    }

    /* ── File operations ─────────────────────────────────────────── */

    /**
     * Encodes the contents of a file into BPE token IDs.
     */
    List<Integer> encodeFilePath(String path) {
        javaEncoding.encodeFilePath(path).toList()
    }

    /**
     * Counts tokens in a file.
     */
    int countFilePath(String path) {
        javaEncoding.countFilePath(path)
    }

    /**
     * Checks if a file's contents are within the token limit.
     */
    Integer isFilePathWithinTokenLimit(String path, int limit) {
        def result = javaEncoding.isFilePathWithinTokenLimit(path, limit)
        result.present ? result.asInt : null
    }

    /* ── Groovy-idiomatic operators ──────────────────────────────── */

    /**
     * Operator overload: enc &lt;&lt; "hello" returns encoded tokens.
     */
    List<Integer> leftShift(String text) {
        encode(text)
    }

    /**
     * GString support: enc << "hello ${name}" works transparently.
     */
    List<Integer> leftShift(GString text) {
        encode(text.toString())
    }
}
