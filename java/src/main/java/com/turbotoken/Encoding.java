package com.turbotoken;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.OptionalInt;

/**
 * A loaded BPE encoding. Thread-safe after construction.
 *
 * Use {@link TurboToken#getEncoding(String)} or
 * {@link TurboToken#getEncodingForModel(String)} to obtain instances.
 */
public final class Encoding {

    private final byte[] rankPayload;
    private final Registry.EncodingSpec spec;

    Encoding(byte[] rankPayload, Registry.EncodingSpec spec) {
        this.rankPayload = rankPayload;
        this.spec = spec;
    }

    /** Returns the encoding spec. */
    public Registry.EncodingSpec getSpec() {
        return spec;
    }

    /** Returns the encoding name. */
    public String getName() {
        return spec.getName();
    }

    /* ── Core operations ─────────────────────────────────────────────── */

    /**
     * Encodes text into BPE token IDs.
     */
    public int[] encode(String text) {
        byte[] textBytes = text.getBytes(StandardCharsets.UTF_8);
        return NativeBridge.encodeBpe(rankPayload, textBytes);
    }

    /**
     * Decodes BPE token IDs back to a string.
     */
    public String decode(int[] tokens) {
        byte[] bytes = NativeBridge.decodeBpe(rankPayload, tokens);
        return new String(bytes, StandardCharsets.UTF_8);
    }

    /**
     * Counts the number of tokens in the given text without allocating the token array.
     */
    public int count(String text) {
        byte[] textBytes = text.getBytes(StandardCharsets.UTF_8);
        long c = NativeBridge.countBpe(rankPayload, textBytes);
        return (int) c;
    }

    /**
     * Alias for {@link #count(String)}.
     */
    public int countTokens(String text) {
        return count(text);
    }

    /**
     * Checks if the text is within the given token limit.
     * Returns the token count if within the limit, or empty if exceeded.
     */
    public OptionalInt isWithinTokenLimit(String text, int limit) {
        byte[] textBytes = text.getBytes(StandardCharsets.UTF_8);
        long result = NativeBridge.isWithinTokenLimit(rankPayload, textBytes, limit);
        if (result == -2) {
            return OptionalInt.empty();
        }
        return OptionalInt.of((int) result);
    }

    /* ── Chat operations ─────────────────────────────────────────────── */

    /**
     * Encodes a list of chat messages into token IDs.
     */
    public int[] encodeChat(List<ChatTemplate.ChatMessage> messages, ChatTemplate.ChatOptions options) {
        String formatted = ChatTemplate.formatMessages(messages, options);
        return encode(formatted);
    }

    /**
     * Counts tokens in a list of chat messages.
     */
    public int countChat(List<ChatTemplate.ChatMessage> messages, ChatTemplate.ChatOptions options) {
        String formatted = ChatTemplate.formatMessages(messages, options);
        return count(formatted);
    }

    /**
     * Checks if a chat conversation is within the token limit.
     */
    public OptionalInt isChatWithinTokenLimit(List<ChatTemplate.ChatMessage> messages,
                                               ChatTemplate.ChatOptions options, int limit) {
        String formatted = ChatTemplate.formatMessages(messages, options);
        return isWithinTokenLimit(formatted, limit);
    }

    /* ── File operations ─────────────────────────────────────────────── */

    /**
     * Encodes the contents of a file into BPE token IDs.
     */
    public int[] encodeFilePath(String filePath) {
        return NativeBridge.encodeBpeFile(rankPayload, filePath);
    }

    /**
     * Counts tokens in a file without reading it into Java memory.
     */
    public int countFilePath(String filePath) {
        long c = NativeBridge.countBpeFile(rankPayload, filePath);
        return (int) c;
    }

    /**
     * Checks if a file's contents are within the token limit.
     */
    public OptionalInt isFilePathWithinTokenLimit(String filePath, int limit) {
        // File-level limit check goes through encode and checks length
        int[] tokens = encodeFilePath(filePath);
        if (tokens.length <= limit) {
            return OptionalInt.of(tokens.length);
        }
        return OptionalInt.empty();
    }
}
