<?php

declare(strict_types=1);

namespace TurboToken;

class EncodingSpec
{
    public string $name;
    public string $rankFileUrl;
    public string $patStr;
    /** @var array<string, int> */
    public array $specialTokens;
    public int $nVocab;

    /**
     * @param array<string, int> $specialTokens
     */
    public function __construct(
        string $name,
        string $rankFileUrl,
        string $patStr,
        array $specialTokens,
        int $nVocab
    ) {
        $this->name = $name;
        $this->rankFileUrl = $rankFileUrl;
        $this->patStr = $patStr;
        $this->specialTokens = $specialTokens;
        $this->nVocab = $nVocab;
    }

    public function eotToken(): int
    {
        return $this->specialTokens['<|endoftext|>'];
    }
}

class Registry
{
    private const R50K_PAT_STR = "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++$|\\s+(?!\\S)|\\s";

    private const CL100K_PAT_STR = "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s";

    private const O200K_PAT_STR = "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?|[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+";

    /** @var array<string, EncodingSpec> */
    private static array $specs = [];

    /** @var array<string, string> */
    public const MODEL_TO_ENCODING = [
        'o1' => 'o200k_base',
        'o3' => 'o200k_base',
        'o4-mini' => 'o200k_base',
        'gpt-5' => 'o200k_base',
        'gpt-4.1' => 'o200k_base',
        'gpt-4o' => 'o200k_base',
        'gpt-4o-mini' => 'o200k_base',
        'gpt-4.1-mini' => 'o200k_base',
        'gpt-4.1-nano' => 'o200k_base',
        'gpt-oss-120b' => 'o200k_harmony',
        'gpt-4' => 'cl100k_base',
        'gpt-3.5-turbo' => 'cl100k_base',
        'gpt-3.5' => 'cl100k_base',
        'gpt-35-turbo' => 'cl100k_base',
        'davinci-002' => 'cl100k_base',
        'babbage-002' => 'cl100k_base',
        'text-embedding-ada-002' => 'cl100k_base',
        'text-embedding-3-small' => 'cl100k_base',
        'text-embedding-3-large' => 'cl100k_base',
        'text-davinci-003' => 'p50k_base',
        'text-davinci-002' => 'p50k_base',
        'text-davinci-001' => 'r50k_base',
        'text-curie-001' => 'r50k_base',
        'text-babbage-001' => 'r50k_base',
        'text-ada-001' => 'r50k_base',
        'davinci' => 'r50k_base',
        'curie' => 'r50k_base',
        'babbage' => 'r50k_base',
        'ada' => 'r50k_base',
        'code-davinci-002' => 'p50k_base',
        'code-davinci-001' => 'p50k_base',
        'code-cushman-002' => 'p50k_base',
        'code-cushman-001' => 'p50k_base',
        'davinci-codex' => 'p50k_base',
        'cushman-codex' => 'p50k_base',
        'text-davinci-edit-001' => 'p50k_edit',
        'code-davinci-edit-001' => 'p50k_edit',
        'text-similarity-davinci-001' => 'r50k_base',
        'text-similarity-curie-001' => 'r50k_base',
        'text-similarity-babbage-001' => 'r50k_base',
        'text-similarity-ada-001' => 'r50k_base',
        'text-search-davinci-doc-001' => 'r50k_base',
        'text-search-curie-doc-001' => 'r50k_base',
        'text-search-babbage-doc-001' => 'r50k_base',
        'text-search-ada-doc-001' => 'r50k_base',
        'code-search-babbage-code-001' => 'r50k_base',
        'code-search-ada-code-001' => 'r50k_base',
        'gpt2' => 'gpt2',
        'gpt-2' => 'r50k_base',
    ];

    /** @var array<string, string> */
    public const MODEL_PREFIX_TO_ENCODING = [
        'o1-' => 'o200k_base',
        'o3-' => 'o200k_base',
        'o4-mini-' => 'o200k_base',
        'gpt-5-' => 'o200k_base',
        'gpt-4.5-' => 'o200k_base',
        'gpt-4.1-' => 'o200k_base',
        'chatgpt-4o-' => 'o200k_base',
        'gpt-4o-' => 'o200k_base',
        'gpt-oss-' => 'o200k_harmony',
        'gpt-4-' => 'cl100k_base',
        'gpt-3.5-turbo-' => 'cl100k_base',
        'gpt-35-turbo-' => 'cl100k_base',
        'ft:gpt-4o' => 'o200k_base',
        'ft:gpt-4' => 'cl100k_base',
        'ft:gpt-3.5-turbo' => 'cl100k_base',
        'ft:davinci-002' => 'cl100k_base',
        'ft:babbage-002' => 'cl100k_base',
    ];

    private static function initSpecs(): void
    {
        if (!empty(self::$specs)) {
            return;
        }
        self::$specs = [
            'o200k_base' => new EncodingSpec(
                'o200k_base',
                'https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken',
                self::O200K_PAT_STR,
                ['<|endoftext|>' => 199999, '<|endofprompt|>' => 200018],
                200019
            ),
            'cl100k_base' => new EncodingSpec(
                'cl100k_base',
                'https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken',
                self::CL100K_PAT_STR,
                [
                    '<|endoftext|>' => 100257,
                    '<|fim_prefix|>' => 100258,
                    '<|fim_middle|>' => 100259,
                    '<|fim_suffix|>' => 100260,
                    '<|endofprompt|>' => 100276,
                ],
                100277
            ),
            'p50k_base' => new EncodingSpec(
                'p50k_base',
                'https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken',
                self::R50K_PAT_STR,
                ['<|endoftext|>' => 50256],
                50281
            ),
            'r50k_base' => new EncodingSpec(
                'r50k_base',
                'https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken',
                self::R50K_PAT_STR,
                ['<|endoftext|>' => 50256],
                50257
            ),
            'gpt2' => new EncodingSpec(
                'gpt2',
                'https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken',
                self::R50K_PAT_STR,
                ['<|endoftext|>' => 50256],
                50257
            ),
            'p50k_edit' => new EncodingSpec(
                'p50k_edit',
                'https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken',
                self::R50K_PAT_STR,
                ['<|endoftext|>' => 50256],
                50281
            ),
            'o200k_harmony' => new EncodingSpec(
                'o200k_harmony',
                'https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken',
                self::O200K_PAT_STR,
                ['<|endoftext|>' => 199999, '<|endofprompt|>' => 200018],
                200019
            ),
        ];
    }

    public static function getEncodingSpec(string $name): EncodingSpec
    {
        self::initSpecs();
        if (!isset(self::$specs[$name])) {
            $supported = implode(', ', self::listEncodingNames());
            throw new TurboTokenException("Unknown encoding '$name'. Supported encodings: $supported");
        }
        return self::$specs[$name];
    }

    public static function modelToEncoding(string $model): string
    {
        if (isset(self::MODEL_TO_ENCODING[$model])) {
            return self::MODEL_TO_ENCODING[$model];
        }

        foreach (self::MODEL_PREFIX_TO_ENCODING as $prefix => $encoding) {
            if (strpos($model, $prefix) === 0) {
                return $encoding;
            }
        }

        throw new TurboTokenException(
            "Could not automatically map '$model' to an encoding. "
            . "Use getEncoding(\$name) to select one explicitly."
        );
    }

    /**
     * @return string[]
     */
    public static function listEncodingNames(): array
    {
        self::initSpecs();
        $names = array_keys(self::$specs);
        sort($names);
        return $names;
    }
}
