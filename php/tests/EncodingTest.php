<?php

declare(strict_types=1);

namespace TurboToken\Tests;

use PHPUnit\Framework\TestCase;
use TurboToken\TurboToken;
use TurboToken\Registry;

class EncodingTest extends TestCase
{
    public function testEncodeDecodeRoundTrip(): void
    {
        $enc = TurboToken::getEncoding('cl100k_base');
        $text = 'hello world';
        $tokens = $enc->encode($text);

        $this->assertIsArray($tokens);
        $this->assertNotEmpty($tokens);

        $decoded = $enc->decode($tokens);
        $this->assertSame($text, $decoded);
    }

    public function testCount(): void
    {
        $enc = TurboToken::getEncoding('cl100k_base');
        $text = 'hello world';
        $count = $enc->count($text);

        $this->assertIsInt($count);
        $this->assertGreaterThan(0, $count);
        $this->assertSame(count($enc->encode($text)), $count);
    }

    public function testGetEncoding(): void
    {
        $enc = TurboToken::getEncoding('o200k_base');
        $this->assertSame('o200k_base', $enc->name());
        $this->assertSame(200019, $enc->nVocab());
    }

    public function testGetEncodingForModel(): void
    {
        $enc = TurboToken::getEncodingForModel('gpt-4o');
        $this->assertSame('o200k_base', $enc->name());
    }

    public function testListEncodingNames(): void
    {
        $names = TurboToken::listEncodingNames();
        $this->assertContains('cl100k_base', $names);
        $this->assertContains('o200k_base', $names);
        $this->assertContains('r50k_base', $names);
    }

    public function testModelToEncoding(): void
    {
        $this->assertSame('o200k_base', Registry::modelToEncoding('gpt-4o'));
        $this->assertSame('cl100k_base', Registry::modelToEncoding('gpt-4'));
        $this->assertSame('r50k_base', Registry::modelToEncoding('davinci'));
    }

    public function testUnknownEncodingThrows(): void
    {
        $this->expectException(\TurboToken\TurboTokenException::class);
        TurboToken::getEncoding('nonexistent_encoding');
    }

    public function testUnknownModelThrows(): void
    {
        $this->expectException(\TurboToken\TurboTokenException::class);
        Registry::modelToEncoding('totally-unknown-model');
    }

    public function testIsWithinTokenLimit(): void
    {
        $enc = TurboToken::getEncoding('cl100k_base');
        $text = 'hello world';

        // Large limit should return token count
        $result = $enc->isWithinTokenLimit($text, 1000);
        $this->assertIsInt($result);
        $this->assertGreaterThan(0, $result);

        // Zero limit should return null (exceeded)
        $result = $enc->isWithinTokenLimit($text, 0);
        $this->assertNull($result);
    }

    public function testCountTokensAlias(): void
    {
        $enc = TurboToken::getEncoding('cl100k_base');
        $text = 'hello world';
        $this->assertSame($enc->count($text), $enc->countTokens($text));
    }
}
