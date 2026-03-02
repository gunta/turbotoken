package com.turbotoken;

import java.util.List;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Main entry point for the turbotoken Java API.
 *
 * <pre>{@code
 * Encoding enc = TurboToken.getEncoding("cl100k_base");
 * int[] tokens = enc.encode("hello world");
 * String decoded = enc.decode(tokens);
 *
 * // Or by model name:
 * Encoding enc2 = TurboToken.getEncodingForModel("gpt-4o");
 * }</pre>
 */
public final class TurboToken {

    private static final ConcurrentHashMap<String, Encoding> CACHE = new ConcurrentHashMap<>();

    private TurboToken() {}

    /**
     * Returns the native library version string.
     */
    public static String version() {
        return NativeBridge.version();
    }

    /**
     * Returns an Encoding for the given encoding name (e.g. "cl100k_base", "o200k_base").
     * Encoding instances are cached and reused.
     * @throws IllegalArgumentException if the encoding name is unknown
     */
    public static Encoding getEncoding(String name) {
        return CACHE.computeIfAbsent(name, k -> {
            Registry.EncodingSpec spec = Registry.getEncodingSpec(k);
            byte[] rankPayload = RankCache.readRankFile(k);
            return new Encoding(rankPayload, spec);
        });
    }

    /**
     * Returns an Encoding for the given model name (e.g. "gpt-4o", "gpt-3.5-turbo").
     * @throws IllegalArgumentException if the model cannot be mapped to an encoding
     */
    public static Encoding getEncodingForModel(String model) {
        String encodingName = Registry.modelToEncoding(model);
        return getEncoding(encodingName);
    }

    /**
     * Returns a sorted list of all supported encoding names.
     */
    public static List<String> listEncodingNames() {
        return Registry.listEncodingNames();
    }
}
