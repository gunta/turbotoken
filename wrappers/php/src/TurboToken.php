<?php

declare(strict_types=1);

namespace TurboToken;

class TurboToken
{
    /** @var array<string, Encoding> */
    private static array $cache = [];

    public static function getEncoding(string $name): Encoding
    {
        if (!isset(self::$cache[$name])) {
            $spec = Registry::getEncodingSpec($name);
            $rankPayload = RankCache::readRankFile($name);
            self::$cache[$name] = new Encoding($rankPayload, $spec);
        }
        return self::$cache[$name];
    }

    public static function getEncodingForModel(string $model): Encoding
    {
        $name = Registry::modelToEncoding($model);
        return self::getEncoding($name);
    }

    /**
     * @return string[]
     */
    public static function listEncodingNames(): array
    {
        return Registry::listEncodingNames();
    }

    public static function version(): string
    {
        return NativeBridge::version();
    }
}
