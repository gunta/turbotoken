<?php

declare(strict_types=1);

namespace TurboToken;

class Encoding
{
    private string $rankPayload;
    private EncodingSpec $spec;

    public function __construct(string $rankPayload, EncodingSpec $spec)
    {
        $this->rankPayload = $rankPayload;
        $this->spec = $spec;
    }

    public function name(): string
    {
        return $this->spec->name;
    }

    public function nVocab(): int
    {
        return $this->spec->nVocab;
    }

    public function eotToken(): int
    {
        return $this->spec->eotToken();
    }

    /**
     * @return int[]
     */
    public function encode(string $text): array
    {
        return NativeBridge::encodeBpeFromRanks($this->rankPayload, $text);
    }

    /**
     * @param int[] $tokens
     */
    public function decode(array $tokens): string
    {
        return NativeBridge::decodeBpeFromRanks($this->rankPayload, $tokens);
    }

    public function count(string $text): int
    {
        return NativeBridge::countBpeFromRanks($this->rankPayload, $text);
    }

    public function countTokens(string $text): int
    {
        return $this->count($text);
    }

    /**
     * Returns token count if within limit, null if exceeded.
     */
    public function isWithinTokenLimit(string $text, int $limit): ?int
    {
        return NativeBridge::isWithinTokenLimitBpeFromRanks($this->rankPayload, $text, $limit);
    }

    /**
     * @param ChatMessage[] $messages
     * @param array{template?: string} $opts
     * @return int[]
     */
    public function encodeChat(array $messages, array $opts = []): array
    {
        $template = ChatTemplate::resolveTurboTokenV1();
        $text = $template->formatMessages($messages);
        return $this->encode($text);
    }

    /**
     * @param ChatMessage[] $messages
     * @param array{template?: string} $opts
     */
    public function countChat(array $messages, array $opts = []): int
    {
        $template = ChatTemplate::resolveTurboTokenV1();
        $text = $template->formatMessages($messages);
        return $this->count($text);
    }

    /**
     * @param ChatMessage[] $messages
     * @param array{template?: string} $opts
     */
    public function isChatWithinTokenLimit(array $messages, int $limit, array $opts = []): ?int
    {
        $template = ChatTemplate::resolveTurboTokenV1();
        $text = $template->formatMessages($messages);
        return $this->isWithinTokenLimit($text, $limit);
    }

    /**
     * @return int[]
     */
    public function encodeFilePath(string $filePath): array
    {
        return NativeBridge::encodeBpeFileFromRanks($this->rankPayload, $filePath);
    }

    public function countFilePath(string $filePath): int
    {
        return NativeBridge::countBpeFileFromRanks($this->rankPayload, $filePath);
    }

    public function isFilePathWithinTokenLimit(string $filePath, int $limit): ?int
    {
        return NativeBridge::isWithinTokenLimitBpeFileFromRanks($this->rankPayload, $filePath, $limit);
    }
}
