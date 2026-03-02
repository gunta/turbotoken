package com.turbotoken.rn;

import android.util.Base64;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.WritableArray;

import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;

public class TurboTokenModule extends ReactContextBaseJavaModule {
    static {
        System.loadLibrary("turbotoken");
    }

    // Native JNI methods
    private static native String nativeVersion();
    private static native void nativeClearCache();
    private static native int nativeEncodeBpe(byte[] rankBytes, byte[] text, int[] outTokens);
    private static native int nativeEncodeBpeSize(byte[] rankBytes, byte[] text);
    private static native int nativeDecodeBpe(byte[] rankBytes, int[] tokens, byte[] outBytes);
    private static native int nativeDecodeBpeSize(byte[] rankBytes, int[] tokens);
    private static native int nativeCountBpe(byte[] rankBytes, byte[] text);
    private static native int nativeIsWithinTokenLimit(byte[] rankBytes, byte[] text, int limit);
    private static native int nativeEncodeBpeFile(byte[] rankBytes, byte[] filePath, int[] outTokens);
    private static native int nativeEncodeBpeFileSize(byte[] rankBytes, byte[] filePath);
    private static native int nativeCountBpeFile(byte[] rankBytes, byte[] filePath);

    public TurboTokenModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @Override
    public String getName() {
        return "TurboToken";
    }

    @ReactMethod(isBlockingSynchronousMethod = true)
    public String version() {
        return nativeVersion();
    }

    @ReactMethod(isBlockingSynchronousMethod = true)
    public void clearCache() {
        nativeClearCache();
    }

    @ReactMethod
    public void encodeBpe(String rankBase64, String text, Promise promise) {
        new Thread(() -> {
            try {
                byte[] rankBytes = Base64.decode(rankBase64, Base64.DEFAULT);
                byte[] textBytes = text.getBytes(StandardCharsets.UTF_8);

                int needed = nativeEncodeBpeSize(rankBytes, textBytes);
                if (needed < 0) {
                    promise.reject("E_ENCODE", "BPE encode size query failed");
                    return;
                }

                int[] tokens = new int[needed];
                int written = nativeEncodeBpe(rankBytes, textBytes, tokens);
                if (written < 0) {
                    promise.reject("E_ENCODE", "BPE encode failed");
                    return;
                }

                WritableArray result = Arguments.createArray();
                for (int i = 0; i < written; i++) {
                    result.pushInt(tokens[i]);
                }
                promise.resolve(result);
            } catch (Exception e) {
                promise.reject("E_ENCODE", e.getMessage(), e);
            }
        }).start();
    }

    @ReactMethod
    public void decodeBpe(String rankBase64, ReadableArray tokensArray, Promise promise) {
        new Thread(() -> {
            try {
                byte[] rankBytes = Base64.decode(rankBase64, Base64.DEFAULT);
                int[] tokens = new int[tokensArray.size()];
                for (int i = 0; i < tokensArray.size(); i++) {
                    tokens[i] = tokensArray.getInt(i);
                }

                int needed = nativeDecodeBpeSize(rankBytes, tokens);
                if (needed < 0) {
                    promise.reject("E_DECODE", "BPE decode size query failed");
                    return;
                }

                byte[] outBytes = new byte[needed];
                int written = nativeDecodeBpe(rankBytes, tokens, outBytes);
                if (written < 0) {
                    promise.reject("E_DECODE", "BPE decode failed");
                    return;
                }

                String result = new String(outBytes, 0, written, StandardCharsets.UTF_8);
                promise.resolve(result);
            } catch (Exception e) {
                promise.reject("E_DECODE", e.getMessage(), e);
            }
        }).start();
    }

    @ReactMethod
    public void countBpe(String rankBase64, String text, Promise promise) {
        new Thread(() -> {
            try {
                byte[] rankBytes = Base64.decode(rankBase64, Base64.DEFAULT);
                byte[] textBytes = text.getBytes(StandardCharsets.UTF_8);

                int count = nativeCountBpe(rankBytes, textBytes);
                if (count < 0) {
                    promise.reject("E_COUNT", "BPE count failed");
                    return;
                }
                promise.resolve(count);
            } catch (Exception e) {
                promise.reject("E_COUNT", e.getMessage(), e);
            }
        }).start();
    }

    @ReactMethod
    public void isWithinTokenLimit(String rankBase64, String text, double limit, Promise promise) {
        new Thread(() -> {
            try {
                byte[] rankBytes = Base64.decode(rankBase64, Base64.DEFAULT);
                byte[] textBytes = text.getBytes(StandardCharsets.UTF_8);

                int result = nativeIsWithinTokenLimit(rankBytes, textBytes, (int) limit);
                if (result == -1) {
                    promise.reject("E_LIMIT", "Token limit check failed");
                    return;
                }
                promise.resolve(result);
            } catch (Exception e) {
                promise.reject("E_LIMIT", e.getMessage(), e);
            }
        }).start();
    }

    @ReactMethod
    public void encodeBpeFile(String rankBase64, String filePath, Promise promise) {
        new Thread(() -> {
            try {
                byte[] rankBytes = Base64.decode(rankBase64, Base64.DEFAULT);
                byte[] pathBytes = filePath.getBytes(StandardCharsets.UTF_8);

                int needed = nativeEncodeBpeFileSize(rankBytes, pathBytes);
                if (needed < 0) {
                    promise.reject("E_ENCODE_FILE", "BPE file encode size query failed");
                    return;
                }

                int[] tokens = new int[needed];
                int written = nativeEncodeBpeFile(rankBytes, pathBytes, tokens);
                if (written < 0) {
                    promise.reject("E_ENCODE_FILE", "BPE file encode failed");
                    return;
                }

                WritableArray result = Arguments.createArray();
                for (int i = 0; i < written; i++) {
                    result.pushInt(tokens[i]);
                }
                promise.resolve(result);
            } catch (Exception e) {
                promise.reject("E_ENCODE_FILE", e.getMessage(), e);
            }
        }).start();
    }

    @ReactMethod
    public void countBpeFile(String rankBase64, String filePath, Promise promise) {
        new Thread(() -> {
            try {
                byte[] rankBytes = Base64.decode(rankBase64, Base64.DEFAULT);
                byte[] pathBytes = filePath.getBytes(StandardCharsets.UTF_8);

                int count = nativeCountBpeFile(rankBytes, pathBytes);
                if (count < 0) {
                    promise.reject("E_COUNT_FILE", "BPE file count failed");
                    return;
                }
                promise.resolve(count);
            } catch (Exception e) {
                promise.reject("E_COUNT_FILE", e.getMessage(), e);
            }
        }).start();
    }
}
