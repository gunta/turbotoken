/// Static facade for the turbotoken API.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'encoding.dart';
import 'native_bridge.dart';
import 'rank_cache.dart';
import 'registry.dart' as reg;

final Map<String, Encoding> _cache = {};

class TurboToken {
  TurboToken._();

  /// Get an encoding by name (e.g. "cl100k_base", "o200k_base").
  ///
  /// Downloads the rank file on first use and caches it.
  static Future<Encoding> getEncoding(String name) async {
    if (_cache.containsKey(name)) return _cache[name]!;

    final spec = reg.getEncodingSpec(name);
    final rankPayload = await readRankFile(name);
    final enc = Encoding.fromRankPayload(rankPayload, spec);
    _cache[name] = enc;
    return enc;
  }

  /// Get the encoding for a model name (e.g. "gpt-4o", "gpt-3.5-turbo").
  static Future<Encoding> getEncodingForModel(String model) async {
    final encodingName = reg.modelToEncodingName(model);
    return getEncoding(encodingName);
  }

  /// List all supported encoding names.
  static List<String> listEncodingNames() {
    return reg.listEncodingNames();
  }

  /// Return the turbotoken native library version string.
  static String version() {
    final bridge = getNativeBridge();
    final ptr = bridge.version();
    return ptr.toDartString();
  }

  /// Clear the in-memory encoding cache and the native rank table cache.
  static void clearCache() {
    _cache.clear();
    try {
      final bridge = getNativeBridge();
      bridge.clearCache();
    } catch (_) {
      // Native library may not be loaded yet.
    }
  }
}
