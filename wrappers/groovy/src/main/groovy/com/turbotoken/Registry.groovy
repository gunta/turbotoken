package com.turbotoken

import groovy.transform.Immutable

/**
 * Encoding registry -- maps encoding names and model names to encoding specs.
 * Mirrors the Python _registry.py exactly.
 */
class Registry {

    /* ── Special token constants ─────────────────────────────────── */

    static final String ENDOFTEXT   = '<|endoftext|>'
    static final String FIM_PREFIX  = '<|fim_prefix|>'
    static final String FIM_MIDDLE  = '<|fim_middle|>'
    static final String FIM_SUFFIX  = '<|fim_suffix|>'
    static final String ENDOFPROMPT = '<|endofprompt|>'

    /* ── Pattern strings ────────────────────────────────────────── */

    private static final String R50K_PAT_STR =
        "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++\$|\\s+(?!\\S)|\\s"

    private static final String CL100K_PAT_STR =
        "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++\$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s"

    private static final String O200K_PAT_STR = [
        "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
        "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
        "\\p{N}{1,3}",
        " ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*",
        "\\s*[\\r\\n]+",
        "\\s+(?!\\S)",
        "\\s+"
    ].join('|')

    /* ── EncodingSpec ────────────────────────────────────────────── */

    static class EncodingSpec {
        final String name
        final String rankFileUrl
        final String patStr
        final Map<String, Integer> specialTokens
        final int nVocab

        EncodingSpec(String name, String rankFileUrl, String patStr,
                     Map<String, Integer> specialTokens, int nVocab) {
            this.name = name
            this.rankFileUrl = rankFileUrl
            this.patStr = patStr
            this.specialTokens = Collections.unmodifiableMap(specialTokens)
            this.nVocab = nVocab
        }

        int getEotToken() { specialTokens[ENDOFTEXT] }
    }

    /* ── Encoding specs ─────────────────────────────────────────── */

    private static final Map<String, EncodingSpec> ENCODING_SPECS = [
        'o200k_base': new EncodingSpec(
            'o200k_base',
            'https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken',
            O200K_PAT_STR,
            [(ENDOFTEXT): 199999, (ENDOFPROMPT): 200018],
            200019
        ),
        'cl100k_base': new EncodingSpec(
            'cl100k_base',
            'https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken',
            CL100K_PAT_STR,
            [(ENDOFTEXT): 100257, (FIM_PREFIX): 100258, (FIM_MIDDLE): 100259,
             (FIM_SUFFIX): 100260, (ENDOFPROMPT): 100276],
            100277
        ),
        'p50k_base': new EncodingSpec(
            'p50k_base',
            'https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken',
            R50K_PAT_STR,
            [(ENDOFTEXT): 50256],
            50281
        ),
        'r50k_base': new EncodingSpec(
            'r50k_base',
            'https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken',
            R50K_PAT_STR,
            [(ENDOFTEXT): 50256],
            50257
        ),
        'gpt2': new EncodingSpec(
            'gpt2',
            'https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken',
            R50K_PAT_STR,
            [(ENDOFTEXT): 50256],
            50257
        ),
        'p50k_edit': new EncodingSpec(
            'p50k_edit',
            'https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken',
            R50K_PAT_STR,
            [(ENDOFTEXT): 50256],
            50281
        ),
        'o200k_harmony': new EncodingSpec(
            'o200k_harmony',
            'https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken',
            O200K_PAT_STR,
            [(ENDOFTEXT): 199999, (ENDOFPROMPT): 200018],
            200019
        )
    ].asImmutable()

    /* ── Model-to-encoding mappings ─────────────────────────────── */

    private static final Map<String, String> MODEL_TO_ENCODING = [
        'o1':                              'o200k_base',
        'o3':                              'o200k_base',
        'o4-mini':                         'o200k_base',
        'gpt-5':                           'o200k_base',
        'gpt-4.1':                         'o200k_base',
        'gpt-4o':                          'o200k_base',
        'gpt-4o-mini':                     'o200k_base',
        'gpt-4.1-mini':                    'o200k_base',
        'gpt-4.1-nano':                    'o200k_base',
        'gpt-oss-120b':                    'o200k_harmony',
        'gpt-4':                           'cl100k_base',
        'gpt-3.5-turbo':                   'cl100k_base',
        'gpt-3.5':                         'cl100k_base',
        'gpt-35-turbo':                    'cl100k_base',
        'davinci-002':                     'cl100k_base',
        'babbage-002':                     'cl100k_base',
        'text-embedding-ada-002':          'cl100k_base',
        'text-embedding-3-small':          'cl100k_base',
        'text-embedding-3-large':          'cl100k_base',
        'text-davinci-003':                'p50k_base',
        'text-davinci-002':                'p50k_base',
        'text-davinci-001':                'r50k_base',
        'text-curie-001':                  'r50k_base',
        'text-babbage-001':                'r50k_base',
        'text-ada-001':                    'r50k_base',
        'davinci':                         'r50k_base',
        'curie':                           'r50k_base',
        'babbage':                         'r50k_base',
        'ada':                             'r50k_base',
        'code-davinci-002':                'p50k_base',
        'code-davinci-001':                'p50k_base',
        'code-cushman-002':                'p50k_base',
        'code-cushman-001':                'p50k_base',
        'davinci-codex':                   'p50k_base',
        'cushman-codex':                   'p50k_base',
        'text-davinci-edit-001':           'p50k_edit',
        'code-davinci-edit-001':           'p50k_edit',
        'text-similarity-davinci-001':     'r50k_base',
        'text-similarity-curie-001':       'r50k_base',
        'text-similarity-babbage-001':     'r50k_base',
        'text-similarity-ada-001':         'r50k_base',
        'text-search-davinci-doc-001':     'r50k_base',
        'text-search-curie-doc-001':       'r50k_base',
        'text-search-babbage-doc-001':     'r50k_base',
        'text-search-ada-doc-001':         'r50k_base',
        'code-search-babbage-code-001':    'r50k_base',
        'code-search-ada-code-001':        'r50k_base',
        'gpt2':                            'gpt2',
        'gpt-2':                           'r50k_base'
    ].asImmutable()

    /** Prefix-to-encoding pairs. Order matters -- checked sequentially. */
    private static final List<Map.Entry<String, String>> MODEL_PREFIX_TO_ENCODING = [
        entry('o1-',               'o200k_base'),
        entry('o3-',               'o200k_base'),
        entry('o4-mini-',          'o200k_base'),
        entry('gpt-5-',            'o200k_base'),
        entry('gpt-4.5-',          'o200k_base'),
        entry('gpt-4.1-',          'o200k_base'),
        entry('chatgpt-4o-',       'o200k_base'),
        entry('gpt-4o-',           'o200k_base'),
        entry('gpt-oss-',          'o200k_harmony'),
        entry('gpt-4-',            'cl100k_base'),
        entry('gpt-3.5-turbo-',    'cl100k_base'),
        entry('gpt-35-turbo-',     'cl100k_base'),
        entry('ft:gpt-4o',         'o200k_base'),
        entry('ft:gpt-4',          'cl100k_base'),
        entry('ft:gpt-3.5-turbo',  'cl100k_base'),
        entry('ft:davinci-002',    'cl100k_base'),
        entry('ft:babbage-002',    'cl100k_base')
    ].asImmutable()

    private static Map.Entry<String, String> entry(String k, String v) {
        new AbstractMap.SimpleImmutableEntry<>(k, v)
    }

    /* ── Public API ─────────────────────────────────────────────── */

    /**
     * Returns the EncodingSpec for the given encoding name.
     * @throws IllegalArgumentException if the encoding name is unknown
     */
    static EncodingSpec getEncodingSpec(String name) {
        def spec = ENCODING_SPECS[name]
        if (spec == null) {
            throw new IllegalArgumentException(
                "Unknown encoding '${name}'. Supported encodings: ${listEncodingNames().join(', ')}"
            )
        }
        spec
    }

    /**
     * Maps a model name to its encoding name.
     * Tries exact match first, then prefix match.
     * @throws IllegalArgumentException if the model cannot be mapped
     */
    static String modelToEncoding(String model) {
        def enc = MODEL_TO_ENCODING[model]
        if (enc != null) return enc

        for (e in MODEL_PREFIX_TO_ENCODING) {
            if (model.startsWith(e.key)) {
                return e.value
            }
        }

        throw new IllegalArgumentException(
            "Could not automatically map '${model}' to an encoding. " +
            "Use getEncoding(name) to select one explicitly."
        )
    }

    /**
     * Returns a sorted list of all supported encoding names.
     */
    static List<String> listEncodingNames() {
        ENCODING_SPECS.keySet().sort()
    }
}
