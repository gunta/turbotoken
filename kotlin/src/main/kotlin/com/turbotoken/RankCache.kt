@file:JvmName("KRankCache")
package com.turbotoken

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.file.Path

/**
 * Kotlin wrapper around the Java RankCache with coroutine-friendly suspend variants.
 */
object KotlinRankCache {

    /**
     * Returns the cache directory path.
     */
    fun getCacheDir(): Path = RankCache.getCacheDir()

    /**
     * Ensures the rank file is downloaded and cached. Returns the file path.
     */
    fun ensureRankFile(encodingName: String): Path =
        RankCache.ensureRankFile(encodingName)

    /**
     * Reads the rank file bytes, downloading if necessary.
     */
    fun readRankFile(encodingName: String): ByteArray =
        RankCache.readRankFile(encodingName)

    /**
     * Suspend variant -- downloads the rank file on the IO dispatcher.
     */
    suspend fun ensureRankFileSuspend(encodingName: String): Path =
        withContext(Dispatchers.IO) {
            RankCache.ensureRankFile(encodingName)
        }

    /**
     * Suspend variant -- reads rank file bytes on the IO dispatcher.
     */
    suspend fun readRankFileSuspend(encodingName: String): ByteArray =
        withContext(Dispatchers.IO) {
            RankCache.readRankFile(encodingName)
        }
}
