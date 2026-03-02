package com.turbotoken

import java.util.concurrent.ConcurrentHashMap

/**
 * Main entry point for the turbotoken Groovy API.
 *
 * <pre>
 * def enc = TurboToken.getEncoding('cl100k_base')
 * def tokens = enc.encode('hello world')
 * def decoded = enc.decode(tokens)
 *
 * // Or by model name:
 * def enc2 = TurboToken.getEncodingForModel('gpt-4o')
 *
 * // Groovy operator:
 * def tokens2 = enc << 'hello world'
 * </pre>
 */
class TurboToken {

    private static final ConcurrentHashMap<String, Encoding> CACHE = new ConcurrentHashMap<>()

    private TurboToken() {}

    /**
     * Returns the native library version string.
     */
    static String getVersion() {
        com.turbotoken.TurboToken.version()
    }

    /**
     * Returns an Encoding for the given encoding name (e.g. "cl100k_base", "o200k_base").
     * Encoding instances are cached and reused.
     *
     * @throws IllegalArgumentException if the encoding name is unknown
     */
    static Encoding getEncoding(String name) {
        CACHE.computeIfAbsent(name) { k ->
            // Validate the name exists in our registry
            Registry.getEncodingSpec(k)
            // Delegate to Java for actual native loading
            def javaEnc = com.turbotoken.TurboToken.getEncoding(k)
            new Encoding(javaEnc)
        }
    }

    /**
     * Returns an Encoding for the given model name (e.g. "gpt-4o", "gpt-3.5-turbo").
     *
     * @throws IllegalArgumentException if the model cannot be mapped to an encoding
     */
    static Encoding getEncodingForModel(String model) {
        def encodingName = Registry.modelToEncoding(model)
        getEncoding(encodingName)
    }

    /**
     * Returns a sorted list of all supported encoding names.
     */
    static List<String> listEncodingNames() {
        Registry.listEncodingNames()
    }
}
