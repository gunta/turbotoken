<?php

declare(strict_types=1);

namespace TurboToken;

class ChatMessage
{
    public string $role;
    public string $content;
    public ?string $name;

    public function __construct(string $role, string $content, ?string $name = null)
    {
        $this->role = $role;
        $this->content = $content;
        $this->name = $name;
    }
}

class ChatTemplate
{
    public string $messagePrefix;
    public string $messageSuffix;
    public string $assistantPrefix;

    public function __construct(
        string $messagePrefix,
        string $messageSuffix,
        string $assistantPrefix
    ) {
        $this->messagePrefix = $messagePrefix;
        $this->messageSuffix = $messageSuffix;
        $this->assistantPrefix = $assistantPrefix;
    }

    /**
     * @param ChatMessage[] $messages
     */
    public function formatMessages(array $messages): string
    {
        $text = '';
        foreach ($messages as $msg) {
            $nameTag = $msg->name !== null ? " name={$msg->name}" : '';
            $text .= $this->messagePrefix
                . "<|im_start|>{$msg->role}{$nameTag}\n"
                . $msg->content
                . "<|im_end|>"
                . $this->messageSuffix;
        }
        $text .= $this->assistantPrefix;
        return $text;
    }

    public static function resolveTurboTokenV1(): self
    {
        return new self('', "\n", "<|im_start|>assistant\n");
    }

    public static function resolveImTokens(): self
    {
        return new self('', "\n", "<|im_start|>assistant\n");
    }
}
