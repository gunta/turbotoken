/// turbotoken — the fastest BPE tokenizer on every platform.
///
/// Drop-in replacement for tiktoken with Zig + hand-written assembly core.
library turbotoken;

export 'src/turbotoken.dart' show TurboToken;
export 'src/encoding.dart' show Encoding;
export 'src/chat.dart' show ChatMessage, ChatTemplate, ChatTemplateMode, ChatOptions;
export 'src/error.dart'
    show TurbotokenException, EncodingException, UnknownEncodingException, DownloadException;
export 'src/registry.dart' show EncodingSpec;
