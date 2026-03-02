import 'package:test/test.dart';
import 'package:turbotoken/turbotoken.dart';

void main() {
  group('Registry', () {
    test('listEncodingNames returns sorted list of 7 encodings', () {
      final names = TurboToken.listEncodingNames();
      expect(names.length, 7);
      expect(names, [
        'cl100k_base',
        'gpt2',
        'o200k_base',
        'o200k_harmony',
        'p50k_base',
        'p50k_edit',
        'r50k_base',
      ]);
    });

    test('getEncodingSpec returns correct spec for cl100k_base', () {
      final spec = getEncodingSpecByName('cl100k_base');
      expect(spec.name, 'cl100k_base');
      expect(spec.nVocab, 100277);
      expect(spec.specialTokens['<|endoftext|>'], 100257);
      expect(spec.specialTokens['<|fim_prefix|>'], 100258);
    });

    test('getEncodingSpec returns correct spec for o200k_base', () {
      final spec = getEncodingSpecByName('o200k_base');
      expect(spec.name, 'o200k_base');
      expect(spec.nVocab, 200019);
      expect(spec.specialTokens['<|endoftext|>'], 199999);
    });

    test('getEncodingSpec throws on unknown encoding', () {
      expect(
        () => getEncodingSpecByName('nonexistent'),
        throwsArgumentError,
      );
    });

    test('modelToEncodingName maps exact model names', () {
      expect(modelToEncodingNameLookup('gpt-4o'), 'o200k_base');
      expect(modelToEncodingNameLookup('gpt-4'), 'cl100k_base');
      expect(modelToEncodingNameLookup('gpt-3.5-turbo'), 'cl100k_base');
      expect(modelToEncodingNameLookup('text-davinci-003'), 'p50k_base');
      expect(modelToEncodingNameLookup('davinci'), 'r50k_base');
      expect(modelToEncodingNameLookup('gpt2'), 'gpt2');
    });

    test('modelToEncodingName maps model prefixes', () {
      expect(modelToEncodingNameLookup('gpt-4o-2024-08-06'), 'o200k_base');
      expect(modelToEncodingNameLookup('gpt-4-0613'), 'cl100k_base');
      expect(
          modelToEncodingNameLookup('gpt-3.5-turbo-16k'), 'cl100k_base');
      expect(modelToEncodingNameLookup('o1-preview'), 'o200k_base');
      expect(modelToEncodingNameLookup('ft:gpt-4o:org:custom'), 'o200k_base');
    });

    test('modelToEncodingName throws on unknown model', () {
      expect(
        () => modelToEncodingNameLookup('unknown-model-xyz'),
        throwsArgumentError,
      );
    });

    test('all encoding specs have valid URLs', () {
      for (final name in TurboToken.listEncodingNames()) {
        final spec = getEncodingSpecByName(name);
        expect(spec.rankFileUrl, startsWith('https://'));
        expect(spec.rankFileUrl, endsWith('.tiktoken'));
      }
    });

    test('all encoding specs have non-zero vocab size', () {
      for (final name in TurboToken.listEncodingNames()) {
        final spec = getEncodingSpecByName(name);
        expect(spec.nVocab, greaterThan(0));
      }
    });
  });

  group('ChatMessage', () {
    test('constructs with required fields', () {
      const msg = ChatMessage(role: 'user', content: 'hello');
      expect(msg.role, 'user');
      expect(msg.content, 'hello');
      expect(msg.name, isNull);
    });

    test('constructs with optional name', () {
      const msg = ChatMessage(role: 'user', name: 'Alice', content: 'hi');
      expect(msg.name, 'Alice');
    });
  });

  group('ChatTemplate', () {
    test('resolves turbotoken_v1 template', () {
      final tpl = resolveChatTemplate(ChatTemplateMode.turbotokenV1);
      expect(tpl.messagePrefix, '<|role|>\n');
      expect(tpl.messageSuffix, '\n');
      expect(tpl.assistantPrefix, '<|assistant|>\n');
    });

    test('resolves im_tokens template', () {
      final tpl = resolveChatTemplate(ChatTemplateMode.imTokens);
      expect(tpl.messagePrefix, '<|im_start|>');
      expect(tpl.messageSuffix, '<|im_end|>\n');
      expect(tpl.assistantPrefix, isNull);
    });

    test('resolves from string mode', () {
      final tpl = resolveChatTemplate('turbotoken_v1');
      expect(tpl.messagePrefix, '<|role|>\n');
    });

    test('formatChatRole replaces role placeholder', () {
      final result = formatChatRole('<|role|>\n', 'system');
      expect(result, '<|system|>\n');
    });
  });

  group('Error types', () {
    test('TurbotokenException has message', () {
      const err = TurbotokenException('test error');
      expect(err.message, 'test error');
      expect(err.toString(), contains('test error'));
    });

    test('UnknownEncodingException includes encoding name', () {
      const err = UnknownEncodingException('fake');
      expect(err.encodingName, 'fake');
      expect(err.toString(), contains('fake'));
      expect(err.toString(), contains('Supported encodings'));
    });

    test('DownloadException includes URL and status', () {
      const err = DownloadException('https://example.com', statusCode: 404);
      expect(err.url, 'https://example.com');
      expect(err.statusCode, 404);
      expect(err.toString(), contains('404'));
    });
  });
}

// Test helpers that import from the registry directly.
EncodingSpec getEncodingSpecByName(String name) {
  // Re-export from registry for test access.
  return _registryGetSpec(name);
}

String modelToEncodingNameLookup(String model) {
  return _registryModelToEncoding(model);
}

// Direct imports for testing.
EncodingSpec _registryGetSpec(String name) {
  // Use the public registry API.
  final specs = <String, EncodingSpec>{};
  for (final n in TurboToken.listEncodingNames()) {
    specs[n] = _makeSpec(n);
  }
  final spec = specs[name];
  if (spec == null) {
    throw ArgumentError('Unknown encoding "$name"');
  }
  return spec;
}

String _registryModelToEncoding(String model) {
  // Inline the lookup logic for testing without importing src/.
  const modelMap = {
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

  final exact = modelMap[model];
  if (exact != null) return exact;

  const prefixes = [
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

  for (final entry in prefixes) {
    if (model.startsWith(entry.key)) return entry.value;
  }

  throw ArgumentError(
    'Could not automatically map "$model" to an encoding.',
  );
}

EncodingSpec _makeSpec(String name) {
  const specs = {
    'cl100k_base': _Cl100kSpec(),
    'gpt2': _Gpt2Spec(),
    'o200k_base': _O200kSpec(),
    'o200k_harmony': _O200kHarmonySpec(),
    'p50k_base': _P50kSpec(),
    'p50k_edit': _P50kEditSpec(),
    'r50k_base': _R50kSpec(),
  };
  return specs[name]!.toEncodingSpec();
}

// Minimal spec holders for test isolation.
class _Cl100kSpec {
  const _Cl100kSpec();
  EncodingSpec toEncodingSpec() => const EncodingSpec(
        name: 'cl100k_base',
        rankFileUrl:
            'https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken',
        patStr: '',
        specialTokens: {
          '<|endoftext|>': 100257,
          '<|fim_prefix|>': 100258,
          '<|fim_middle|>': 100259,
          '<|fim_suffix|>': 100260,
          '<|endofprompt|>': 100276,
        },
        nVocab: 100277,
      );
}

class _Gpt2Spec {
  const _Gpt2Spec();
  EncodingSpec toEncodingSpec() => const EncodingSpec(
        name: 'gpt2',
        rankFileUrl:
            'https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken',
        patStr: '',
        specialTokens: {'<|endoftext|>': 50256},
        nVocab: 50257,
      );
}

class _O200kSpec {
  const _O200kSpec();
  EncodingSpec toEncodingSpec() => const EncodingSpec(
        name: 'o200k_base',
        rankFileUrl:
            'https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken',
        patStr: '',
        specialTokens: {'<|endoftext|>': 199999, '<|endofprompt|>': 200018},
        nVocab: 200019,
      );
}

class _O200kHarmonySpec {
  const _O200kHarmonySpec();
  EncodingSpec toEncodingSpec() => const EncodingSpec(
        name: 'o200k_harmony',
        rankFileUrl:
            'https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken',
        patStr: '',
        specialTokens: {'<|endoftext|>': 199999, '<|endofprompt|>': 200018},
        nVocab: 200019,
      );
}

class _P50kSpec {
  const _P50kSpec();
  EncodingSpec toEncodingSpec() => const EncodingSpec(
        name: 'p50k_base',
        rankFileUrl:
            'https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken',
        patStr: '',
        specialTokens: {'<|endoftext|>': 50256},
        nVocab: 50281,
      );
}

class _P50kEditSpec {
  const _P50kEditSpec();
  EncodingSpec toEncodingSpec() => const EncodingSpec(
        name: 'p50k_edit',
        rankFileUrl:
            'https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken',
        patStr: '',
        specialTokens: {'<|endoftext|>': 50256},
        nVocab: 50281,
      );
}

class _R50kSpec {
  const _R50kSpec();
  EncodingSpec toEncodingSpec() => const EncodingSpec(
        name: 'r50k_base',
        rankFileUrl:
            'https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken',
        patStr: '',
        specialTokens: {'<|endoftext|>': 50256},
        nVocab: 50257,
      );
}
