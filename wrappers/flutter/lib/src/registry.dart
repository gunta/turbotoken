/// Encoding specifications and model-to-encoding mappings.
///
/// Ported from Python turbotoken/_registry.py — values must stay in sync.

class EncodingSpec {
  final String name;
  final String rankFileUrl;
  final String patStr;
  final Map<String, int> specialTokens;
  final int nVocab;

  const EncodingSpec({
    required this.name,
    required this.rankFileUrl,
    required this.patStr,
    required this.specialTokens,
    required this.nVocab,
  });
}

// Special token constants.
const String _endOfText = '<|endoftext|>';
const String _fimPrefix = '<|fim_prefix|>';
const String _fimMiddle = '<|fim_middle|>';
const String _fimSuffix = '<|fim_suffix|>';
const String _endOfPrompt = '<|endofprompt|>';

// Pattern strings (from Python _registry.py).
const String _r50kPatStr =
    r"""'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s""";

const String _cl100kPatStr =
    r"""'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s""";

final String _o200kPatStr = [
  r"""[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
  r"""[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?""",
  r"""\p{N}{1,3}""",
  r""" ?[^\s\p{L}\p{N}]+[\r\n/]*""",
  r"""\s*[\r\n]+""",
  r"""\s+(?!\S)""",
  r"""\s+""",
].join('|');

// All 7 encoding specifications.
final Map<String, EncodingSpec> encodingSpecs = {
  'o200k_base': EncodingSpec(
    name: 'o200k_base',
    rankFileUrl:
        'https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken',
    patStr: _o200kPatStr,
    specialTokens: {_endOfText: 199999, _endOfPrompt: 200018},
    nVocab: 200019,
  ),
  'cl100k_base': EncodingSpec(
    name: 'cl100k_base',
    rankFileUrl:
        'https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken',
    patStr: _cl100kPatStr,
    specialTokens: {
      _endOfText: 100257,
      _fimPrefix: 100258,
      _fimMiddle: 100259,
      _fimSuffix: 100260,
      _endOfPrompt: 100276,
    },
    nVocab: 100277,
  ),
  'p50k_base': EncodingSpec(
    name: 'p50k_base',
    rankFileUrl:
        'https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken',
    patStr: _r50kPatStr,
    specialTokens: {_endOfText: 50256},
    nVocab: 50281,
  ),
  'r50k_base': EncodingSpec(
    name: 'r50k_base',
    rankFileUrl:
        'https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken',
    patStr: _r50kPatStr,
    specialTokens: {_endOfText: 50256},
    nVocab: 50257,
  ),
  'gpt2': EncodingSpec(
    name: 'gpt2',
    rankFileUrl:
        'https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken',
    patStr: _r50kPatStr,
    specialTokens: {_endOfText: 50256},
    nVocab: 50257,
  ),
  'p50k_edit': EncodingSpec(
    name: 'p50k_edit',
    rankFileUrl:
        'https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken',
    patStr: _r50kPatStr,
    specialTokens: {_endOfText: 50256},
    nVocab: 50281,
  ),
  'o200k_harmony': EncodingSpec(
    name: 'o200k_harmony',
    rankFileUrl:
        'https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken',
    patStr: _o200kPatStr,
    specialTokens: {_endOfText: 199999, _endOfPrompt: 200018},
    nVocab: 200019,
  ),
};

// Exact model name to encoding.
const Map<String, String> modelToEncoding = {
  'o1': 'o200k_base',
  'o3': 'o200k_base',
  'o4-mini': 'o200k_base',
  'gpt-5': 'o200k_base',
  'gpt-4.1': 'o200k_base',
  'gpt-4o': 'o200k_base',
  'gpt-4o-mini': 'o200k_base',
  'gpt-4.1-mini': 'o200k_base',
  'gpt-4.1-nano': 'o200k_base',
  'gpt-oss-120b': 'o200k_harmony',
  'gpt-4': 'cl100k_base',
  'gpt-3.5-turbo': 'cl100k_base',
  'gpt-3.5': 'cl100k_base',
  'gpt-35-turbo': 'cl100k_base',
  'davinci-002': 'cl100k_base',
  'babbage-002': 'cl100k_base',
  'text-embedding-ada-002': 'cl100k_base',
  'text-embedding-3-small': 'cl100k_base',
  'text-embedding-3-large': 'cl100k_base',
  'text-davinci-003': 'p50k_base',
  'text-davinci-002': 'p50k_base',
  'text-davinci-001': 'r50k_base',
  'text-curie-001': 'r50k_base',
  'text-babbage-001': 'r50k_base',
  'text-ada-001': 'r50k_base',
  'davinci': 'r50k_base',
  'curie': 'r50k_base',
  'babbage': 'r50k_base',
  'ada': 'r50k_base',
  'code-davinci-002': 'p50k_base',
  'code-davinci-001': 'p50k_base',
  'code-cushman-002': 'p50k_base',
  'code-cushman-001': 'p50k_base',
  'davinci-codex': 'p50k_base',
  'cushman-codex': 'p50k_base',
  'text-davinci-edit-001': 'p50k_edit',
  'code-davinci-edit-001': 'p50k_edit',
  'text-similarity-davinci-001': 'r50k_base',
  'text-similarity-curie-001': 'r50k_base',
  'text-similarity-babbage-001': 'r50k_base',
  'text-similarity-ada-001': 'r50k_base',
  'text-search-davinci-doc-001': 'r50k_base',
  'text-search-curie-doc-001': 'r50k_base',
  'text-search-babbage-doc-001': 'r50k_base',
  'text-search-ada-doc-001': 'r50k_base',
  'code-search-babbage-code-001': 'r50k_base',
  'code-search-ada-code-001': 'r50k_base',
  'gpt2': 'gpt2',
  'gpt-2': 'r50k_base',
};

// Model prefix to encoding (order matters — checked sequentially).
const List<MapEntry<String, String>> modelPrefixToEncoding = [
  MapEntry('o1-', 'o200k_base'),
  MapEntry('o3-', 'o200k_base'),
  MapEntry('o4-mini-', 'o200k_base'),
  MapEntry('gpt-5-', 'o200k_base'),
  MapEntry('gpt-4.5-', 'o200k_base'),
  MapEntry('gpt-4.1-', 'o200k_base'),
  MapEntry('chatgpt-4o-', 'o200k_base'),
  MapEntry('gpt-4o-', 'o200k_base'),
  MapEntry('gpt-oss-', 'o200k_harmony'),
  MapEntry('gpt-4-', 'cl100k_base'),
  MapEntry('gpt-3.5-turbo-', 'cl100k_base'),
  MapEntry('gpt-35-turbo-', 'cl100k_base'),
  MapEntry('ft:gpt-4o', 'o200k_base'),
  MapEntry('ft:gpt-4', 'cl100k_base'),
  MapEntry('ft:gpt-3.5-turbo', 'cl100k_base'),
  MapEntry('ft:davinci-002', 'cl100k_base'),
  MapEntry('ft:babbage-002', 'cl100k_base'),
];

EncodingSpec getEncodingSpec(String name) {
  final spec = encodingSpecs[name];
  if (spec == null) {
    throw ArgumentError(
      'Unknown encoding "$name". '
      'Supported encodings: ${listEncodingNames().join(', ')}',
    );
  }
  return spec;
}

String modelToEncodingName(String model) {
  final exact = modelToEncoding[model];
  if (exact != null) return exact;

  for (final entry in modelPrefixToEncoding) {
    if (model.startsWith(entry.key)) {
      return entry.value;
    }
  }

  throw ArgumentError(
    'Could not automatically map "$model" to an encoding. '
    'Use getEncoding(name) to select one explicitly.',
  );
}

List<String> listEncodingNames() {
  final names = encodingSpecs.keys.toList();
  names.sort();
  return names;
}
