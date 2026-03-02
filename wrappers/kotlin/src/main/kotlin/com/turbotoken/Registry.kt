@file:JvmName("KRegistry")
package com.turbotoken

/**
 * Kotlin-idiomatic access to the encoding registry.
 * Delegates to the Java Registry.
 */
object EncodingRegistry {

    /**
     * Returns the EncodingSpec for the given encoding name.
     * @throws IllegalArgumentException if the encoding name is unknown
     */
    fun getEncodingSpec(name: String): Registry.EncodingSpec =
        Registry.getEncodingSpec(name)

    /**
     * Maps a model name to its encoding name.
     * @throws IllegalArgumentException if the model cannot be mapped
     */
    fun modelToEncoding(model: String): String =
        Registry.modelToEncoding(model)

    /**
     * Returns a sorted list of all supported encoding names.
     */
    fun listEncodingNames(): List<String> =
        Registry.listEncodingNames()

    /**
     * Returns the EncodingSpec for the given name, or null if not found.
     */
    fun getEncodingSpecOrNull(name: String): Registry.EncodingSpec? =
        try {
            Registry.getEncodingSpec(name)
        } catch (_: IllegalArgumentException) {
            null
        }

    /**
     * Maps a model name to its encoding name, or null if not found.
     */
    fun modelToEncodingOrNull(model: String): String? =
        try {
            Registry.modelToEncoding(model)
        } catch (_: IllegalArgumentException) {
            null
        }
}
