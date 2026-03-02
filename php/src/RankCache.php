<?php

declare(strict_types=1);

namespace TurboToken;

class RankCache
{
    public static function getCacheDir(): string
    {
        $env = getenv('TURBOTOKEN_CACHE_DIR');
        if ($env !== false && $env !== '') {
            return $env;
        }

        $home = getenv('HOME') ?: (getenv('USERPROFILE') ?: sys_get_temp_dir());
        return $home . DIRECTORY_SEPARATOR . '.cache' . DIRECTORY_SEPARATOR . 'turbotoken';
    }

    public static function ensureRankFile(string $name): string
    {
        $spec = Registry::getEncodingSpec($name);
        $cacheDir = self::getCacheDir();

        if (!is_dir($cacheDir)) {
            if (!mkdir($cacheDir, 0755, true) && !is_dir($cacheDir)) {
                throw new TurboTokenException("Failed to create cache directory: $cacheDir");
            }
        }

        $filePath = $cacheDir . DIRECTORY_SEPARATOR . $spec->name . '.tiktoken';

        if (file_exists($filePath)) {
            return $filePath;
        }

        $context = stream_context_create([
            'http' => [
                'timeout' => 60,
                'user_agent' => 'turbotoken-php/0.1.0',
            ],
        ]);

        $data = @file_get_contents($spec->rankFileUrl, false, $context);
        if ($data === false) {
            throw new TurboTokenException("Failed to download rank file from: {$spec->rankFileUrl}");
        }

        if (file_put_contents($filePath, $data) === false) {
            throw new TurboTokenException("Failed to write rank file to: $filePath");
        }

        return $filePath;
    }

    public static function readRankFile(string $name): string
    {
        $filePath = self::ensureRankFile($name);
        $data = file_get_contents($filePath);
        if ($data === false) {
            throw new TurboTokenException("Failed to read rank file: $filePath");
        }
        return $data;
    }
}
