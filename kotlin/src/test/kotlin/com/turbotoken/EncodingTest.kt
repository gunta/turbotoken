package com.turbotoken

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Tests for turbotoken Kotlin bindings.
 */
class KEncodingTest {

    @Test
    fun `registry lists all encoding names`() {
        val names = EncodingRegistry.listEncodingNames()
        assertNotNull(names)
        assertTrue(names.contains("cl100k_base"))
        assertTrue(names.contains("o200k_base"))
        assertTrue(names.contains("p50k_base"))
        assertTrue(names.contains("r50k_base"))
        assertTrue(names.contains("gpt2"))
        assertTrue(names.contains("p50k_edit"))
        assertTrue(names.contains("o200k_harmony"))
        assertEquals(7, names.size)
    }

    @Test
    fun `registry get encoding spec`() {
        val spec = EncodingRegistry.getEncodingSpec("cl100k_base")
        assertEquals("cl100k_base", spec.name)
        assertEquals(100277, spec.nVocab)
        assertEquals(100257, spec.eotToken)
    }

    @Test
    fun `registry get encoding spec or null returns null for unknown`() {
        val spec = EncodingRegistry.getEncodingSpecOrNull("nonexistent")
        assertNull(spec)
    }

    @Test
    fun `registry model to encoding`() {
        assertEquals("o200k_base", EncodingRegistry.modelToEncoding("gpt-4o"))
        assertEquals("cl100k_base", EncodingRegistry.modelToEncoding("gpt-4"))
        assertEquals("r50k_base", EncodingRegistry.modelToEncoding("davinci"))
    }

    @Test
    fun `registry model to encoding or null returns null for unknown`() {
        val enc = EncodingRegistry.modelToEncodingOrNull("unknown-model-xyz")
        assertNull(enc)
    }

    @Test
    fun `registry model to encoding prefix match`() {
        assertEquals("o200k_base", EncodingRegistry.modelToEncoding("gpt-4o-2024-08-06"))
        assertEquals("cl100k_base", EncodingRegistry.modelToEncoding("gpt-4-turbo-preview"))
    }

    @Test
    fun `turbotoken list encoding names`() {
        val names = TurboTokenK.listEncodingNames()
        assertNotNull(names)
        assertEquals(7, names.size)
    }

    @Test
    fun `chat template resolve`() {
        val template = resolveTemplate(KTemplateMode.TurbotokenV1)
        assertNotNull(template.messagePrefix)
        assertNotNull(template.messageSuffix)
        assertNotNull(template.assistantPrefix)
    }

    @Test
    fun `chat template format messages`() {
        val messages = listOf(
            KChatMessage(role = "system", content = "You are helpful."),
            KChatMessage(role = "user", content = "Hello!")
        )
        val formatted = formatMessages(messages)
        assertTrue(formatted.contains("system"))
        assertTrue(formatted.contains("You are helpful."))
        assertTrue(formatted.contains("user"))
        assertTrue(formatted.contains("Hello!"))
    }

    @Test
    fun `chat message with name`() {
        val msg = KChatMessage(role = "user", content = "Hi", name = "Alice")
        assertEquals("user", msg.role)
        assertEquals("Hi", msg.content)
        assertEquals("Alice", msg.name)
    }

    /* ── Native tests (require library loaded) ───────────────────────── */

    @Test
    @EnabledIfEnvironmentVariable(named = "TURBOTOKEN_NATIVE_LIB", matches = ".+")
    fun `encode decode round trip`() {
        val enc = TurboTokenK.getEncoding("cl100k_base")
        val original = "hello world"
        val tokens = enc.encode(original)
        assertNotNull(tokens)
        assertTrue(tokens.isNotEmpty())
        val decoded = enc.decode(tokens)
        assertEquals(original, decoded)
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "TURBOTOKEN_NATIVE_LIB", matches = ".+")
    fun `count tokens`() {
        val enc = TurboTokenK.getEncoding("cl100k_base")
        val count = enc.count("hello world")
        assertTrue(count > 0)
        val tokens = enc.encode("hello world")
        assertEquals(tokens.size, count)
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "TURBOTOKEN_NATIVE_LIB", matches = ".+")
    fun `extension function token count`() {
        val enc = TurboTokenK.getEncoding("cl100k_base")
        val count = "hello world".tokenCount(enc)
        assertTrue(count > 0)
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "TURBOTOKEN_NATIVE_LIB", matches = ".+")
    fun `extension function encode`() {
        val enc = TurboTokenK.getEncoding("cl100k_base")
        val tokens = "hello world".encode(enc)
        assertNotNull(tokens)
        assertTrue(tokens.isNotEmpty())
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "TURBOTOKEN_NATIVE_LIB", matches = ".+")
    fun `result variant captures errors gracefully`() {
        val enc = TurboTokenK.getEncoding("cl100k_base")
        val result = enc.encodeResult("test string")
        assertTrue(result.isSuccess)
        assertNotNull(result.getOrNull())
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "TURBOTOKEN_NATIVE_LIB", matches = ".+")
    fun `get encoding for model`() {
        val enc = TurboTokenK.getEncodingForModel("gpt-4o")
        assertEquals("o200k_base", enc.name)
        val tokens = enc.encode("test")
        assertNotNull(tokens)
        assertTrue(tokens.isNotEmpty())
    }
}
