/// Exception types for turbotoken.
class TurbotokenException implements Exception {
  final String message;

  const TurbotokenException(this.message);

  @override
  String toString() => 'TurbotokenException: $message';
}

class EncodingException extends TurbotokenException {
  const EncodingException(super.message);

  @override
  String toString() => 'EncodingException: $message';
}

class UnknownEncodingException extends TurbotokenException {
  final String encodingName;

  const UnknownEncodingException(this.encodingName)
      : super('Unknown encoding "$encodingName"');

  @override
  String toString() {
    final supported = listSupportedEncodings().join(', ');
    return 'UnknownEncodingException: Unknown encoding "$encodingName". '
        'Supported encodings: $supported';
  }

  static List<String> listSupportedEncodings() {
    return [
      'cl100k_base',
      'gpt2',
      'o200k_base',
      'o200k_harmony',
      'p50k_base',
      'p50k_edit',
      'r50k_base',
    ];
  }
}

class DownloadException extends TurbotokenException {
  final String url;
  final int? statusCode;

  const DownloadException(this.url, {this.statusCode})
      : super('Failed to download rank file from $url');

  @override
  String toString() {
    final suffix = statusCode != null ? ' (HTTP $statusCode)' : '';
    return 'DownloadException: Failed to download rank file from $url$suffix';
  }
}
