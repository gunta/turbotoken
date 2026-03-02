package com.turbotoken;

/**
 * JNI native method declarations matching jni/turbotoken_jni.c.
 * Package-private -- not part of the public API.
 */
final class NativeBridge {

    static {
        NativeLoader.load();
    }

    private NativeBridge() {}

    static native String version();

    static native void clearRankTableCache();

    static native int[] encodeBpe(byte[] rankBytes, byte[] textBytes);

    static native byte[] decodeBpe(byte[] rankBytes, int[] tokens);

    static native long countBpe(byte[] rankBytes, byte[] textBytes);

    static native long isWithinTokenLimit(byte[] rankBytes, byte[] textBytes, long tokenLimit);

    static native int[] encodeBpeFile(byte[] rankBytes, String filePath);

    static native long countBpeFile(byte[] rankBytes, String filePath);

    static native int[] trainBpeFromChunkCounts(
        byte[] chunks, int[] chunkOffsets, int[] chunkCounts,
        int vocabSize, int minFrequency
    );
}
