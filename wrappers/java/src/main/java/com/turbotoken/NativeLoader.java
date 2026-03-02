package com.turbotoken;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Locale;

/**
 * Loads the turbotoken native library using a multi-strategy approach:
 * 1. TURBOTOKEN_NATIVE_LIB environment variable (absolute path)
 * 2. META-INF/native/{os}/{arch}/ embedded in the JAR
 * 3. System library path (java.library.path)
 * 4. zig-out/lib/ relative to working directory
 */
final class NativeLoader {

    private static volatile boolean loaded = false;

    private NativeLoader() {}

    static synchronized void load() {
        if (loaded) {
            return;
        }

        // Strategy 1: explicit env var
        String envPath = System.getenv("TURBOTOKEN_NATIVE_LIB");
        if (envPath != null && !envPath.isEmpty()) {
            System.load(envPath);
            loaded = true;
            return;
        }

        // Strategy 2: extract from JAR resource
        if (tryLoadFromJar()) {
            loaded = true;
            return;
        }

        // Strategy 3: system library path
        try {
            System.loadLibrary("turbotoken");
            loaded = true;
            return;
        } catch (UnsatisfiedLinkError ignored) {
        }

        // Strategy 4: zig-out/lib/
        if (tryLoadFromZigOut()) {
            loaded = true;
            return;
        }

        throw new TurboTokenException(
            "Failed to load turbotoken native library. Set TURBOTOKEN_NATIVE_LIB "
            + "to the absolute path of the shared library, or ensure it is on java.library.path."
        );
    }

    private static boolean tryLoadFromJar() {
        String os = detectOs();
        String arch = detectArch();
        String libName = System.mapLibraryName("turbotoken");
        String resourcePath = "/META-INF/native/" + os + "/" + arch + "/" + libName;

        try (InputStream in = NativeLoader.class.getResourceAsStream(resourcePath)) {
            if (in == null) {
                return false;
            }
            Path tempDir = Files.createTempDirectory("turbotoken-native");
            tempDir.toFile().deleteOnExit();
            Path tempLib = tempDir.resolve(libName);
            tempLib.toFile().deleteOnExit();
            Files.copy(in, tempLib, StandardCopyOption.REPLACE_EXISTING);
            System.load(tempLib.toAbsolutePath().toString());
            return true;
        } catch (IOException | UnsatisfiedLinkError e) {
            return false;
        }
    }

    private static boolean tryLoadFromZigOut() {
        String libName = System.mapLibraryName("turbotoken");
        File candidate = new File("zig-out/lib/" + libName);
        if (candidate.exists()) {
            try {
                System.load(candidate.getAbsolutePath());
                return true;
            } catch (UnsatisfiedLinkError ignored) {
            }
        }
        return false;
    }

    private static String detectOs() {
        String os = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
        if (os.contains("mac") || os.contains("darwin")) {
            return "darwin";
        } else if (os.contains("win")) {
            return "windows";
        } else {
            return "linux";
        }
    }

    private static String detectArch() {
        String arch = System.getProperty("os.arch", "").toLowerCase(Locale.ROOT);
        if (arch.equals("aarch64") || arch.equals("arm64")) {
            return "aarch64";
        } else if (arch.equals("amd64") || arch.equals("x86_64")) {
            return "x86_64";
        } else {
            return arch;
        }
    }
}
