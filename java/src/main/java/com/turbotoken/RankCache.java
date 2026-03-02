package com.turbotoken;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Downloads and caches rank files for BPE encodings.
 * Cache directory: TURBOTOKEN_CACHE_DIR env or ~/.cache/turbotoken/
 */
final class RankCache {

    private RankCache() {}

    static Path getCacheDir() {
        String envDir = System.getenv("TURBOTOKEN_CACHE_DIR");
        if (envDir != null && !envDir.isEmpty()) {
            return Paths.get(envDir);
        }
        return Paths.get(System.getProperty("user.home"), ".cache", "turbotoken");
    }

    /**
     * Ensures the rank file for the given encoding name is cached locally.
     * Downloads it from the spec's URL if missing.
     * @return the path to the cached rank file
     */
    static Path ensureRankFile(String encodingName) {
        Registry.EncodingSpec spec = Registry.getEncodingSpec(encodingName);
        String fileName = encodingName + ".tiktoken";
        Path cacheDir = getCacheDir();
        Path cached = cacheDir.resolve(fileName);

        if (Files.exists(cached)) {
            return cached;
        }

        try {
            Files.createDirectories(cacheDir);

            HttpClient client = HttpClient.newHttpClient();
            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(spec.getRankFileUrl()))
                .GET()
                .build();
            HttpResponse<byte[]> response = client.send(request, HttpResponse.BodyHandlers.ofByteArray());

            if (response.statusCode() != 200) {
                throw new TurboTokenException(
                    "Failed to download rank file for " + encodingName
                    + ": HTTP " + response.statusCode()
                );
            }

            Files.write(cached, response.body());
            return cached;

        } catch (IOException | InterruptedException e) {
            throw new TurboTokenException("Failed to download rank file for " + encodingName, e);
        }
    }

    /**
     * Reads the rank file bytes for the given encoding name,
     * downloading it first if not cached.
     */
    static byte[] readRankFile(String encodingName) {
        Path path = ensureRankFile(encodingName);
        try {
            return Files.readAllBytes(path);
        } catch (IOException e) {
            throw new TurboTokenException("Failed to read rank file: " + path, e);
        }
    }
}
