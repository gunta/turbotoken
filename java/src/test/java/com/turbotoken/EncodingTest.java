package com.turbotoken;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Tests for turbotoken Java bindings.
 * Tests marked with @EnabledIfEnvironmentVariable require the native library.
 */
class EncodingTest {

    @Test
    void registryListEncodingNames() {
        List<String> names = Registry.listEncodingNames();
        assertNotNull(names);
        assertTrue(names.contains("cl100k_base"));
        assertTrue(names.contains("o200k_base"));
        assertTrue(names.contains("p50k_base"));
        assertTrue(names.contains("r50k_base"));
        assertTrue(names.contains("gpt2"));
        assertTrue(names.contains("p50k_edit"));
        assertTrue(names.contains("o200k_harmony"));
        assertEquals(7, names.size());
    }

    @Test
    void registryGetEncodingSpec() {
        Registry.EncodingSpec spec = Registry.getEncodingSpec("cl100k_base");
        assertEquals("cl100k_base", spec.getName());
        assertEquals(100277, spec.getNVocab());
        assertEquals(100257, spec.getEotToken());
        assertTrue(spec.getRankFileUrl().contains("cl100k_base.tiktoken"));
    }

    @Test
    void registryGetEncodingSpecUnknown() {
        assertThrows(IllegalArgumentException.class, () -> Registry.getEncodingSpec("nonexistent"));
    }

    @Test
    void registryModelToEncoding() {
        assertEquals("o200k_base", Registry.modelToEncoding("gpt-4o"));
        assertEquals("cl100k_base", Registry.modelToEncoding("gpt-4"));
        assertEquals("r50k_base", Registry.modelToEncoding("davinci"));
        assertEquals("p50k_base", Registry.modelToEncoding("text-davinci-003"));
    }

    @Test
    void registryModelToEncodingPrefix() {
        assertEquals("o200k_base", Registry.modelToEncoding("gpt-4o-2024-08-06"));
        assertEquals("cl100k_base", Registry.modelToEncoding("gpt-4-turbo-preview"));
        assertEquals("o200k_base", Registry.modelToEncoding("o1-preview"));
    }

    @Test
    void registryModelToEncodingUnknown() {
        assertThrows(IllegalArgumentException.class, () -> Registry.modelToEncoding("unknown-model-xyz"));
    }

    @Test
    void turboTokenListEncodings() {
        List<String> names = TurboToken.listEncodingNames();
        assertNotNull(names);
        assertEquals(7, names.size());
    }

    @Test
    void chatTemplateResolve() {
        ChatTemplate.Template template = ChatTemplate.resolve(ChatTemplate.TemplateMode.TURBOTOKEN_V1);
        assertNotNull(template.getMessagePrefix());
        assertNotNull(template.getMessageSuffix());
        assertNotNull(template.getAssistantPrefix());
    }

    @Test
    void chatTemplateFormat() {
        List<ChatTemplate.ChatMessage> messages = List.of(
            new ChatTemplate.ChatMessage("system", "You are helpful."),
            new ChatTemplate.ChatMessage("user", "Hello!")
        );
        ChatTemplate.ChatOptions options = new ChatTemplate.ChatOptions();
        String formatted = ChatTemplate.formatMessages(messages, options);
        assertTrue(formatted.contains("system"));
        assertTrue(formatted.contains("You are helpful."));
        assertTrue(formatted.contains("user"));
        assertTrue(formatted.contains("Hello!"));
    }

    /* ── Native tests (require library loaded) ───────────────────────── */

    @Test
    @EnabledIfEnvironmentVariable(named = "TURBOTOKEN_NATIVE_LIB", matches = ".+")
    void encodeDecodeRoundTrip() {
        Encoding enc = TurboToken.getEncoding("cl100k_base");
        String original = "hello world";
        int[] tokens = enc.encode(original);
        assertNotNull(tokens);
        assertTrue(tokens.length > 0);
        String decoded = enc.decode(tokens);
        assertEquals(original, decoded);
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "TURBOTOKEN_NATIVE_LIB", matches = ".+")
    void count() {
        Encoding enc = TurboToken.getEncoding("cl100k_base");
        int count = enc.count("hello world");
        assertTrue(count > 0);
        int[] tokens = enc.encode("hello world");
        assertEquals(tokens.length, count);
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "TURBOTOKEN_NATIVE_LIB", matches = ".+")
    void getEncodingByModel() {
        Encoding enc = TurboToken.getEncodingForModel("gpt-4o");
        assertEquals("o200k_base", enc.getName());
        int[] tokens = enc.encode("test");
        assertNotNull(tokens);
        assertTrue(tokens.length > 0);
    }
}
