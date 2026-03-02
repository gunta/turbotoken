package com.turbotoken

/**
 * Kotlin-side wrapper around the Java NativeBridge.
 * Delegates all native calls to the Java JNI bridge.
 */
internal object KNativeBridge {

    fun version(): String = NativeBridge.version()

    fun clearRankTableCache() = NativeBridge.clearRankTableCache()

    fun encodeBpe(rankBytes: ByteArray, textBytes: ByteArray): IntArray =
        NativeBridge.encodeBpe(rankBytes, textBytes)

    fun decodeBpe(rankBytes: ByteArray, tokens: IntArray): ByteArray =
        NativeBridge.decodeBpe(rankBytes, tokens)

    fun countBpe(rankBytes: ByteArray, textBytes: ByteArray): Long =
        NativeBridge.countBpe(rankBytes, textBytes)

    fun isWithinTokenLimit(rankBytes: ByteArray, textBytes: ByteArray, tokenLimit: Long): Long =
        NativeBridge.isWithinTokenLimit(rankBytes, textBytes, tokenLimit)

    fun encodeBpeFile(rankBytes: ByteArray, filePath: String): IntArray =
        NativeBridge.encodeBpeFile(rankBytes, filePath)

    fun countBpeFile(rankBytes: ByteArray, filePath: String): Long =
        NativeBridge.countBpeFile(rankBytes, filePath)

    fun trainBpeFromChunkCounts(
        chunks: ByteArray,
        chunkOffsets: IntArray,
        chunkCounts: IntArray,
        vocabSize: Int,
        minFrequency: Int
    ): IntArray = NativeBridge.trainBpeFromChunkCounts(
        chunks, chunkOffsets, chunkCounts, vocabSize, minFrequency
    )
}
