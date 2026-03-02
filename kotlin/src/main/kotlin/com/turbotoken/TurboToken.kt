@file:JvmName("KTurboToken")
package com.turbotoken

import java.util.concurrent.ConcurrentHashMap

/**
 * Main entry point for the turbotoken Kotlin API.
 *
 * ```kotlin
 * val enc = TurboTokenK.getEncoding("cl100k_base")
 * val tokens = enc.encode("hello world")
 * val decoded = enc.decode(tokens)
 *
 * // Or by model name:
 * val enc2 = TurboTokenK.getEncodingForModel("gpt-4o")
 *
 * // Extension functions:
 * val count = "hello world".tokenCount(enc)
 * ```
 */
object TurboTokenK {

    private val cache = ConcurrentHashMap<String, KEncoding>()

    /**
     * Returns the native library version string.
     */
    fun version(): String = KNativeBridge.version()

    /**
     * Returns a KEncoding for the given encoding name.
     * Encoding instances are cached and reused.
     * @throws IllegalArgumentException if the encoding name is unknown
     */
    fun getEncoding(name: String): KEncoding =
        cache.computeIfAbsent(name) {
            KEncoding(TurboToken.getEncoding(it))
        }

    /**
     * Returns a KEncoding for the given model name.
     * @throws IllegalArgumentException if the model cannot be mapped to an encoding
     */
    fun getEncodingForModel(model: String): KEncoding {
        val encodingName = EncodingRegistry.modelToEncoding(model)
        return getEncoding(encodingName)
    }

    /**
     * Returns a sorted list of all supported encoding names.
     */
    fun listEncodingNames(): List<String> = EncodingRegistry.listEncodingNames()

    companion object {
        /**
         * Static access for Java interop.
         */
        @JvmStatic
        fun getEncodingStatic(name: String): KEncoding = getEncoding(name)

        @JvmStatic
        fun getEncodingForModelStatic(model: String): KEncoding = getEncodingForModel(model)

        @JvmStatic
        fun listEncodingNamesStatic(): List<String> = listEncodingNames()

        @JvmStatic
        fun versionStatic(): String = version()
    }
}
