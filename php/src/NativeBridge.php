<?php

declare(strict_types=1);

namespace TurboToken;

use FFI;

class NativeBridge
{
    private static ?FFI $ffi = null;

    private const CDEF = <<<'CDEF'
const char *turbotoken_version(void);
void turbotoken_clear_rank_table_cache(void);

ptrdiff_t turbotoken_count(const uint8_t *text, size_t text_len);

ptrdiff_t turbotoken_encode_utf8_bytes(
    const uint8_t *text, size_t text_len,
    uint32_t *out_tokens, size_t out_cap);

ptrdiff_t turbotoken_decode_utf8_bytes(
    const uint32_t *tokens, size_t token_len,
    uint8_t *out_bytes, size_t out_cap);

ptrdiff_t turbotoken_encode_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    uint32_t *out_tokens, size_t out_cap);

ptrdiff_t turbotoken_decode_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint32_t *tokens, size_t token_len,
    uint8_t *out_bytes, size_t out_cap);

ptrdiff_t turbotoken_count_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len);

ptrdiff_t turbotoken_is_within_token_limit_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    size_t token_limit);

ptrdiff_t turbotoken_encode_bpe_file_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *file_path, size_t file_path_len,
    uint32_t *out_tokens, size_t out_cap);

ptrdiff_t turbotoken_count_bpe_file_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *file_path, size_t file_path_len);

ptrdiff_t turbotoken_is_within_token_limit_bpe_file_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *file_path, size_t file_path_len,
    size_t token_limit);
CDEF;

    private static function findLibrary(): string
    {
        // 1. Environment variable
        $env = getenv('TURBOTOKEN_NATIVE_LIB');
        if ($env !== false && file_exists($env)) {
            return $env;
        }

        $names = PHP_OS_FAMILY === 'Windows'
            ? ['turbotoken.dll']
            : (PHP_OS_FAMILY === 'Darwin'
                ? ['libturbotoken.dylib', 'libturbotoken.so']
                : ['libturbotoken.so']);

        // 2. Bundled alongside this file
        $bundledDir = __DIR__ . '/../lib';
        foreach ($names as $name) {
            $path = $bundledDir . '/' . $name;
            if (file_exists($path)) {
                return $path;
            }
        }

        // 3. zig-out/lib/ relative to project root
        $zigOut = __DIR__ . '/../../zig-out/lib';
        foreach ($names as $name) {
            $path = $zigOut . '/' . $name;
            if (file_exists($path)) {
                return $path;
            }
        }

        // 4. System search (let FFI::cdef + ffi_load handle it)
        return $names[0];
    }

    public static function ffi(): FFI
    {
        if (self::$ffi === null) {
            $lib = self::findLibrary();
            self::$ffi = FFI::cdef(self::CDEF, $lib);
        }
        return self::$ffi;
    }

    public static function version(): string
    {
        return FFI::string(self::ffi()->turbotoken_version());
    }

    public static function clearRankTableCache(): void
    {
        self::ffi()->turbotoken_clear_rank_table_cache();
    }

    public static function encodeBpeFromRanks(
        string $rankBytes,
        string $text
    ): array {
        $ffi = self::ffi();
        $rankLen = strlen($rankBytes);
        $textLen = strlen($text);

        // Pass 1: query size
        $n = $ffi->turbotoken_encode_bpe_from_ranks(
            $rankBytes, $rankLen,
            $text, $textLen,
            null, 0
        );
        if ($n < 0) {
            throw new TurboTokenException("turbotoken_encode_bpe_from_ranks failed (pass 1): code $n");
        }
        if ($n === 0) {
            return [];
        }

        // Pass 2: fill buffer
        $buf = FFI::new("uint32_t[$n]");
        $written = $ffi->turbotoken_encode_bpe_from_ranks(
            $rankBytes, $rankLen,
            $text, $textLen,
            $buf, $n
        );
        if ($written < 0) {
            throw new TurboTokenException("turbotoken_encode_bpe_from_ranks failed (pass 2): code $written");
        }

        $tokens = [];
        for ($i = 0; $i < $written; $i++) {
            $tokens[] = $buf[$i];
        }
        return $tokens;
    }

    public static function decodeBpeFromRanks(
        string $rankBytes,
        array $tokens
    ): string {
        $ffi = self::ffi();
        $rankLen = strlen($rankBytes);
        $tokenLen = count($tokens);

        if ($tokenLen === 0) {
            return '';
        }

        $tokenBuf = FFI::new("uint32_t[$tokenLen]");
        for ($i = 0; $i < $tokenLen; $i++) {
            $tokenBuf[$i] = $tokens[$i];
        }

        // Pass 1: query size
        $n = $ffi->turbotoken_decode_bpe_from_ranks(
            $rankBytes, $rankLen,
            $tokenBuf, $tokenLen,
            null, 0
        );
        if ($n < 0) {
            throw new TurboTokenException("turbotoken_decode_bpe_from_ranks failed (pass 1): code $n");
        }
        if ($n === 0) {
            return '';
        }

        // Pass 2: fill buffer
        $outBuf = FFI::new("uint8_t[$n]");
        $written = $ffi->turbotoken_decode_bpe_from_ranks(
            $rankBytes, $rankLen,
            $tokenBuf, $tokenLen,
            $outBuf, $n
        );
        if ($written < 0) {
            throw new TurboTokenException("turbotoken_decode_bpe_from_ranks failed (pass 2): code $written");
        }

        return FFI::string($outBuf, $written);
    }

    public static function countBpeFromRanks(
        string $rankBytes,
        string $text
    ): int {
        $n = self::ffi()->turbotoken_count_bpe_from_ranks(
            $rankBytes, strlen($rankBytes),
            $text, strlen($text)
        );
        if ($n < 0) {
            throw new TurboTokenException("turbotoken_count_bpe_from_ranks failed: code $n");
        }
        return (int)$n;
    }

    public static function isWithinTokenLimitBpeFromRanks(
        string $rankBytes,
        string $text,
        int $tokenLimit
    ): ?int {
        $result = self::ffi()->turbotoken_is_within_token_limit_bpe_from_ranks(
            $rankBytes, strlen($rankBytes),
            $text, strlen($text),
            $tokenLimit
        );
        if ($result === -1) {
            throw new TurboTokenException("turbotoken_is_within_token_limit_bpe_from_ranks failed");
        }
        if ($result === -2) {
            return null; // limit exceeded
        }
        return (int)$result;
    }

    public static function encodeBpeFileFromRanks(
        string $rankBytes,
        string $filePath
    ): array {
        $ffi = self::ffi();
        $rankLen = strlen($rankBytes);
        $pathLen = strlen($filePath);

        // Pass 1: query size
        $n = $ffi->turbotoken_encode_bpe_file_from_ranks(
            $rankBytes, $rankLen,
            $filePath, $pathLen,
            null, 0
        );
        if ($n < 0) {
            throw new TurboTokenException("turbotoken_encode_bpe_file_from_ranks failed (pass 1): code $n");
        }
        if ($n === 0) {
            return [];
        }

        // Pass 2: fill buffer
        $buf = FFI::new("uint32_t[$n]");
        $written = $ffi->turbotoken_encode_bpe_file_from_ranks(
            $rankBytes, $rankLen,
            $filePath, $pathLen,
            $buf, $n
        );
        if ($written < 0) {
            throw new TurboTokenException("turbotoken_encode_bpe_file_from_ranks failed (pass 2): code $written");
        }

        $tokens = [];
        for ($i = 0; $i < $written; $i++) {
            $tokens[] = $buf[$i];
        }
        return $tokens;
    }

    public static function countBpeFileFromRanks(
        string $rankBytes,
        string $filePath
    ): int {
        $n = self::ffi()->turbotoken_count_bpe_file_from_ranks(
            $rankBytes, strlen($rankBytes),
            $filePath, strlen($filePath)
        );
        if ($n < 0) {
            throw new TurboTokenException("turbotoken_count_bpe_file_from_ranks failed: code $n");
        }
        return (int)$n;
    }

    public static function isWithinTokenLimitBpeFileFromRanks(
        string $rankBytes,
        string $filePath,
        int $tokenLimit
    ): ?int {
        $result = self::ffi()->turbotoken_is_within_token_limit_bpe_file_from_ranks(
            $rankBytes, strlen($rankBytes),
            $filePath, strlen($filePath),
            $tokenLimit
        );
        if ($result === -1) {
            throw new TurboTokenException("turbotoken_is_within_token_limit_bpe_file_from_ranks failed");
        }
        if ($result === -2) {
            return null; // limit exceeded
        }
        return (int)$result;
    }
}
