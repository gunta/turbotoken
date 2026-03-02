/// dart:ffi bindings to turbotoken C ABI.
///
/// Loads the platform-specific shared library and looks up all C function pointers.

import 'dart:ffi';
import 'dart:io' show Platform;

// ── C function typedefs ──────────────────────────────────────────────

// turbotoken_version
typedef TurbotokenVersionC = Pointer<Utf8> Function();
typedef TurbotokenVersionDart = Pointer<Utf8> Function();

// turbotoken_clear_rank_table_cache
typedef ClearCacheC = Void Function();
typedef ClearCacheDart = void Function();

// turbotoken_encode_bpe_from_ranks
typedef EncodeBpeC = IntPtr Function(
  Pointer<Uint8> rankBytes,
  IntPtr rankLen,
  Pointer<Uint8> text,
  IntPtr textLen,
  Pointer<Uint32> outTokens,
  IntPtr outCap,
);
typedef EncodeBpeDart = int Function(
  Pointer<Uint8> rankBytes,
  int rankLen,
  Pointer<Uint8> text,
  int textLen,
  Pointer<Uint32> outTokens,
  int outCap,
);

// turbotoken_decode_bpe_from_ranks
typedef DecodeBpeC = IntPtr Function(
  Pointer<Uint8> rankBytes,
  IntPtr rankLen,
  Pointer<Uint32> tokens,
  IntPtr tokenLen,
  Pointer<Uint8> outBytes,
  IntPtr outCap,
);
typedef DecodeBpeDart = int Function(
  Pointer<Uint8> rankBytes,
  int rankLen,
  Pointer<Uint32> tokens,
  int tokenLen,
  Pointer<Uint8> outBytes,
  int outCap,
);

// turbotoken_count_bpe_from_ranks
typedef CountBpeC = IntPtr Function(
  Pointer<Uint8> rankBytes,
  IntPtr rankLen,
  Pointer<Uint8> text,
  IntPtr textLen,
);
typedef CountBpeDart = int Function(
  Pointer<Uint8> rankBytes,
  int rankLen,
  Pointer<Uint8> text,
  int textLen,
);

// turbotoken_is_within_token_limit_bpe_from_ranks
typedef IsWithinLimitC = IntPtr Function(
  Pointer<Uint8> rankBytes,
  IntPtr rankLen,
  Pointer<Uint8> text,
  IntPtr textLen,
  IntPtr tokenLimit,
);
typedef IsWithinLimitDart = int Function(
  Pointer<Uint8> rankBytes,
  int rankLen,
  Pointer<Uint8> text,
  int textLen,
  int tokenLimit,
);

// turbotoken_encode_bpe_file_from_ranks
typedef EncodeBpeFileC = IntPtr Function(
  Pointer<Uint8> rankBytes,
  IntPtr rankLen,
  Pointer<Uint8> filePath,
  IntPtr filePathLen,
  Pointer<Uint32> outTokens,
  IntPtr outCap,
);
typedef EncodeBpeFileDart = int Function(
  Pointer<Uint8> rankBytes,
  int rankLen,
  Pointer<Uint8> filePath,
  int filePathLen,
  Pointer<Uint32> outTokens,
  int outCap,
);

// turbotoken_count_bpe_file_from_ranks
typedef CountBpeFileC = IntPtr Function(
  Pointer<Uint8> rankBytes,
  IntPtr rankLen,
  Pointer<Uint8> filePath,
  IntPtr filePathLen,
);
typedef CountBpeFileDart = int Function(
  Pointer<Uint8> rankBytes,
  int rankLen,
  Pointer<Uint8> filePath,
  int filePathLen,
);

// turbotoken_is_within_token_limit_bpe_file_from_ranks
typedef IsWithinLimitFileC = IntPtr Function(
  Pointer<Uint8> rankBytes,
  IntPtr rankLen,
  Pointer<Uint8> filePath,
  IntPtr filePathLen,
  IntPtr tokenLimit,
);
typedef IsWithinLimitFileDart = int Function(
  Pointer<Uint8> rankBytes,
  int rankLen,
  Pointer<Uint8> filePath,
  int filePathLen,
  int tokenLimit,
);

// ── Native bridge ────────────────────────────────────────────────────

class NativeBridge {
  late final DynamicLibrary _lib;

  late final TurbotokenVersionDart version;
  late final ClearCacheDart clearCache;
  late final EncodeBpeDart encodeBpe;
  late final DecodeBpeDart decodeBpe;
  late final CountBpeDart countBpe;
  late final IsWithinLimitDart isWithinLimit;
  late final EncodeBpeFileDart encodeBpeFile;
  late final CountBpeFileDart countBpeFile;
  late final IsWithinLimitFileDart isWithinLimitFile;

  NativeBridge() {
    _lib = _openLibrary();
    _lookupAll();
  }

  static DynamicLibrary _openLibrary() {
    // Check environment variable first.
    final envPath = Platform.environment['TURBOTOKEN_NATIVE_LIB'];
    if (envPath != null && envPath.isNotEmpty) {
      return DynamicLibrary.open(envPath);
    }

    if (Platform.isAndroid) {
      return DynamicLibrary.open('libturbotoken.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      // Try framework bundle first, then bare dylib.
      try {
        return DynamicLibrary.open('turbotoken.framework/turbotoken');
      } catch (_) {
        return DynamicLibrary.open('libturbotoken.dylib');
      }
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libturbotoken.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('turbotoken.dll');
    }

    throw UnsupportedError(
      'Unsupported platform: ${Platform.operatingSystem}',
    );
  }

  void _lookupAll() {
    version = _lib
        .lookupFunction<TurbotokenVersionC, TurbotokenVersionDart>(
            'turbotoken_version');

    clearCache = _lib
        .lookupFunction<ClearCacheC, ClearCacheDart>(
            'turbotoken_clear_rank_table_cache');

    encodeBpe = _lib
        .lookupFunction<EncodeBpeC, EncodeBpeDart>(
            'turbotoken_encode_bpe_from_ranks');

    decodeBpe = _lib
        .lookupFunction<DecodeBpeC, DecodeBpeDart>(
            'turbotoken_decode_bpe_from_ranks');

    countBpe = _lib
        .lookupFunction<CountBpeC, CountBpeDart>(
            'turbotoken_count_bpe_from_ranks');

    isWithinLimit = _lib
        .lookupFunction<IsWithinLimitC, IsWithinLimitDart>(
            'turbotoken_is_within_token_limit_bpe_from_ranks');

    encodeBpeFile = _lib
        .lookupFunction<EncodeBpeFileC, EncodeBpeFileDart>(
            'turbotoken_encode_bpe_file_from_ranks');

    countBpeFile = _lib
        .lookupFunction<CountBpeFileC, CountBpeFileDart>(
            'turbotoken_count_bpe_file_from_ranks');

    isWithinLimitFile = _lib
        .lookupFunction<IsWithinLimitFileC, IsWithinLimitFileDart>(
            'turbotoken_is_within_token_limit_bpe_file_from_ranks');
  }
}

// Singleton instance.
NativeBridge? _instance;

NativeBridge getNativeBridge() {
  return _instance ??= NativeBridge();
}
