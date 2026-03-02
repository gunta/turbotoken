/// BPE encoding/decoding using turbotoken's native C ABI.

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'chat.dart';
import 'error.dart';
import 'native_bridge.dart';
import 'registry.dart' as reg;

class Encoding {
  final Uint8List _rankPayload;
  final reg.EncodingSpec _spec;

  Encoding._(this._rankPayload, this._spec);

  static Encoding fromRankPayload(Uint8List rankPayload, reg.EncodingSpec spec) {
    return Encoding._(rankPayload, spec);
  }

  String get name => _spec.name;
  int get nVocab => _spec.nVocab;
  Map<String, int> get specialTokens => _spec.specialTokens;

  /// Encode text to BPE token IDs.
  List<int> encode(String text) {
    final bridge = getNativeBridge();
    final textBytes = utf8.encode(text);

    final rankPtr = calloc<Uint8>(_rankPayload.length);
    final textPtr = calloc<Uint8>(textBytes.length);
    try {
      rankPtr.asTypedList(_rankPayload.length).setAll(0, _rankPayload);
      textPtr.asTypedList(textBytes.length).setAll(0, textBytes);

      // Pass 1: query needed capacity.
      final needed = bridge.encodeBpe(
        rankPtr,
        _rankPayload.length,
        textPtr,
        textBytes.length,
        nullptr,
        0,
      );
      if (needed < 0) {
        throw const EncodingException('encode failed (native returned error)');
      }
      if (needed == 0) return [];

      // Pass 2: encode into allocated buffer.
      final outPtr = calloc<Uint32>(needed);
      try {
        final written = bridge.encodeBpe(
          rankPtr,
          _rankPayload.length,
          textPtr,
          textBytes.length,
          outPtr,
          needed,
        );
        if (written < 0) {
          throw const EncodingException('encode failed (native returned error)');
        }
        return List<int>.generate(written, (i) => outPtr[i]);
      } finally {
        calloc.free(outPtr);
      }
    } finally {
      calloc.free(rankPtr);
      calloc.free(textPtr);
    }
  }

  /// Decode BPE token IDs back to text.
  String decode(List<int> tokens) {
    if (tokens.isEmpty) return '';

    final bridge = getNativeBridge();

    final rankPtr = calloc<Uint8>(_rankPayload.length);
    final tokPtr = calloc<Uint32>(tokens.length);
    try {
      rankPtr.asTypedList(_rankPayload.length).setAll(0, _rankPayload);
      for (var i = 0; i < tokens.length; i++) {
        tokPtr[i] = tokens[i];
      }

      // Pass 1: query needed capacity.
      final needed = bridge.decodeBpe(
        rankPtr,
        _rankPayload.length,
        tokPtr,
        tokens.length,
        nullptr,
        0,
      );
      if (needed < 0) {
        throw const EncodingException('decode failed (native returned error)');
      }
      if (needed == 0) return '';

      // Pass 2: decode into allocated buffer.
      final outPtr = calloc<Uint8>(needed);
      try {
        final written = bridge.decodeBpe(
          rankPtr,
          _rankPayload.length,
          tokPtr,
          tokens.length,
          outPtr,
          needed,
        );
        if (written < 0) {
          throw const EncodingException('decode failed (native returned error)');
        }
        return utf8.decode(outPtr.asTypedList(written), allowMalformed: true);
      } finally {
        calloc.free(outPtr);
      }
    } finally {
      calloc.free(rankPtr);
      calloc.free(tokPtr);
    }
  }

  /// Count BPE tokens without materializing the token array.
  int count(String text) {
    final bridge = getNativeBridge();
    final textBytes = utf8.encode(text);

    final rankPtr = calloc<Uint8>(_rankPayload.length);
    final textPtr = calloc<Uint8>(textBytes.length);
    try {
      rankPtr.asTypedList(_rankPayload.length).setAll(0, _rankPayload);
      textPtr.asTypedList(textBytes.length).setAll(0, textBytes);

      final result = bridge.countBpe(
        rankPtr,
        _rankPayload.length,
        textPtr,
        textBytes.length,
      );
      if (result < 0) {
        throw const EncodingException('count failed (native returned error)');
      }
      return result;
    } finally {
      calloc.free(rankPtr);
      calloc.free(textPtr);
    }
  }

  /// Alias for [count].
  int countTokens(String text) => count(text);

  /// Check if text is within a token limit.
  ///
  /// Returns the token count if within limit, or null if exceeded.
  int? isWithinTokenLimit(String text, int limit) {
    final bridge = getNativeBridge();
    final textBytes = utf8.encode(text);

    final rankPtr = calloc<Uint8>(_rankPayload.length);
    final textPtr = calloc<Uint8>(textBytes.length);
    try {
      rankPtr.asTypedList(_rankPayload.length).setAll(0, _rankPayload);
      textPtr.asTypedList(textBytes.length).setAll(0, textBytes);

      final result = bridge.isWithinLimit(
        rankPtr,
        _rankPayload.length,
        textPtr,
        textBytes.length,
        limit,
      );
      if (result == -2) return null; // Exceeded.
      if (result < 0) {
        throw const EncodingException(
            'isWithinTokenLimit failed (native returned error)');
      }
      return result;
    } finally {
      calloc.free(rankPtr);
      calloc.free(textPtr);
    }
  }

  /// Encode a list of chat messages to token IDs.
  List<int> encodeChat(List<ChatMessage> messages, [ChatOptions? options]) {
    final text = _formatChat(messages, options);
    return encode(text);
  }

  /// Count tokens for a list of chat messages.
  int countChat(List<ChatMessage> messages, [ChatOptions? options]) {
    final text = _formatChat(messages, options);
    return count(text);
  }

  /// Check if chat messages are within a token limit.
  int? isChatWithinTokenLimit(List<ChatMessage> messages, int limit,
      [ChatOptions? options]) {
    final text = _formatChat(messages, options);
    return isWithinTokenLimit(text, limit);
  }

  /// Encode a file's contents to BPE tokens.
  Future<List<int>> encodeFilePath(String path) async {
    final bridge = getNativeBridge();
    final pathBytes = utf8.encode(path);

    final rankPtr = calloc<Uint8>(_rankPayload.length);
    final pathPtr = calloc<Uint8>(pathBytes.length);
    try {
      rankPtr.asTypedList(_rankPayload.length).setAll(0, _rankPayload);
      pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);

      // Pass 1: query needed capacity.
      final needed = bridge.encodeBpeFile(
        rankPtr,
        _rankPayload.length,
        pathPtr,
        pathBytes.length,
        nullptr,
        0,
      );
      if (needed < 0) {
        throw EncodingException('encodeFilePath failed for "$path"');
      }
      if (needed == 0) return [];

      // Pass 2: encode.
      final outPtr = calloc<Uint32>(needed);
      try {
        final written = bridge.encodeBpeFile(
          rankPtr,
          _rankPayload.length,
          pathPtr,
          pathBytes.length,
          outPtr,
          needed,
        );
        if (written < 0) {
          throw EncodingException('encodeFilePath failed for "$path"');
        }
        return List<int>.generate(written, (i) => outPtr[i]);
      } finally {
        calloc.free(outPtr);
      }
    } finally {
      calloc.free(rankPtr);
      calloc.free(pathPtr);
    }
  }

  /// Count BPE tokens in a file.
  Future<int> countFilePath(String path) async {
    final bridge = getNativeBridge();
    final pathBytes = utf8.encode(path);

    final rankPtr = calloc<Uint8>(_rankPayload.length);
    final pathPtr = calloc<Uint8>(pathBytes.length);
    try {
      rankPtr.asTypedList(_rankPayload.length).setAll(0, _rankPayload);
      pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);

      final result = bridge.countBpeFile(
        rankPtr,
        _rankPayload.length,
        pathPtr,
        pathBytes.length,
      );
      if (result < 0) {
        throw EncodingException('countFilePath failed for "$path"');
      }
      return result;
    } finally {
      calloc.free(rankPtr);
      calloc.free(pathPtr);
    }
  }

  /// Check if a file's content is within a token limit.
  Future<int?> isFilePathWithinTokenLimit(String path, int limit) async {
    final bridge = getNativeBridge();
    final pathBytes = utf8.encode(path);

    final rankPtr = calloc<Uint8>(_rankPayload.length);
    final pathPtr = calloc<Uint8>(pathBytes.length);
    try {
      rankPtr.asTypedList(_rankPayload.length).setAll(0, _rankPayload);
      pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);

      final result = bridge.isWithinLimitFile(
        rankPtr,
        _rankPayload.length,
        pathPtr,
        pathBytes.length,
        limit,
      );
      if (result == -2) return null; // Exceeded.
      if (result < 0) {
        throw EncodingException(
            'isFilePathWithinTokenLimit failed for "$path"');
      }
      return result;
    } finally {
      calloc.free(rankPtr);
      calloc.free(pathPtr);
    }
  }

  String _formatChat(List<ChatMessage> messages, ChatOptions? options) {
    final templateMode = options?.template;
    final template = resolveChatTemplate(templateMode);

    final buf = StringBuffer();
    for (final msg in messages) {
      buf.write(formatChatRole(template.messagePrefix, msg.role));
      if (msg.name != null) {
        buf.write('name=${msg.name}\n');
      }
      buf.write(msg.content);
      buf.write(template.messageSuffix);
    }

    if (options?.primeWithAssistantResponse != null) {
      if (template.assistantPrefix != null) {
        buf.write(formatChatRole(template.assistantPrefix!, 'assistant'));
      }
      buf.write(options!.primeWithAssistantResponse!);
    }

    return buf.toString();
  }
}
