package com.turbotoken

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

class EncodingSpecTest extends AnyFunSuite with Matchers {

  /* ── Registry tests ──────────────────────────────────────────── */

  test("listEncodingNames returns all 7 encodings sorted") {
    val names = Registry.listEncodingNames
    names.size shouldBe 7
    names shouldBe names.sorted
    names should contain("o200k_base")
    names should contain("cl100k_base")
    names should contain("p50k_base")
    names should contain("r50k_base")
    names should contain("gpt2")
    names should contain("p50k_edit")
    names should contain("o200k_harmony")
  }

  test("getEncodingSpec returns correct spec for o200k_base") {
    val spec = Registry.getEncodingSpec("o200k_base")
    spec.name shouldBe "o200k_base"
    spec.nVocab shouldBe 200019
    spec.specialTokens("<|endoftext|>") shouldBe 199999
    spec.specialTokens("<|endofprompt|>") shouldBe 200018
  }

  test("getEncodingSpec returns correct spec for cl100k_base") {
    val spec = Registry.getEncodingSpec("cl100k_base")
    spec.name shouldBe "cl100k_base"
    spec.nVocab shouldBe 100277
    spec.specialTokens should have size 5
    spec.specialTokens("<|endoftext|>") shouldBe 100257
    spec.specialTokens("<|fim_prefix|>") shouldBe 100258
    spec.specialTokens("<|fim_middle|>") shouldBe 100259
    spec.specialTokens("<|fim_suffix|>") shouldBe 100260
    spec.specialTokens("<|endofprompt|>") shouldBe 100276
  }

  test("getEncodingSpec returns correct spec for p50k_base") {
    val spec = Registry.getEncodingSpec("p50k_base")
    spec.nVocab shouldBe 50281
    spec.specialTokens("<|endoftext|>") shouldBe 50256
  }

  test("getEncodingSpec returns correct spec for r50k_base") {
    val spec = Registry.getEncodingSpec("r50k_base")
    spec.nVocab shouldBe 50257
  }

  test("getEncodingSpec returns correct spec for gpt2") {
    val spec = Registry.getEncodingSpec("gpt2")
    spec.nVocab shouldBe 50257
    spec.rankFileUrl should include("r50k_base")
  }

  test("getEncodingSpec returns correct spec for p50k_edit") {
    val spec = Registry.getEncodingSpec("p50k_edit")
    spec.nVocab shouldBe 50281
    spec.rankFileUrl should include("p50k_base")
  }

  test("getEncodingSpec returns correct spec for o200k_harmony") {
    val spec = Registry.getEncodingSpec("o200k_harmony")
    spec.nVocab shouldBe 200019
    spec.rankFileUrl should include("o200k_base")
  }

  test("getEncodingSpec throws UnknownEncodingException for unknown name") {
    an [UnknownEncodingException] should be thrownBy {
      Registry.getEncodingSpec("nonexistent")
    }
  }

  /* ── Model resolution tests ──────────────────────────────────── */

  test("modelToEncoding resolves exact model names") {
    Registry.modelToEncoding("gpt-4o") shouldBe "o200k_base"
    Registry.modelToEncoding("gpt-4") shouldBe "cl100k_base"
    Registry.modelToEncoding("gpt-3.5-turbo") shouldBe "cl100k_base"
    Registry.modelToEncoding("text-davinci-003") shouldBe "p50k_base"
    Registry.modelToEncoding("davinci") shouldBe "r50k_base"
    Registry.modelToEncoding("gpt2") shouldBe "gpt2"
    Registry.modelToEncoding("gpt-oss-120b") shouldBe "o200k_harmony"
  }

  test("modelToEncoding resolves prefix matches") {
    Registry.modelToEncoding("gpt-4o-2024-05-13") shouldBe "o200k_base"
    Registry.modelToEncoding("gpt-4-0613") shouldBe "cl100k_base"
    Registry.modelToEncoding("gpt-3.5-turbo-0125") shouldBe "cl100k_base"
    Registry.modelToEncoding("o1-preview") shouldBe "o200k_base"
    Registry.modelToEncoding("o3-mini") shouldBe "o200k_base"
    Registry.modelToEncoding("gpt-oss-beta") shouldBe "o200k_harmony"
  }

  test("modelToEncoding resolves fine-tune prefixes") {
    Registry.modelToEncoding("ft:gpt-4o:myorg") shouldBe "o200k_base"
    Registry.modelToEncoding("ft:gpt-4:myorg") shouldBe "cl100k_base"
    Registry.modelToEncoding("ft:gpt-3.5-turbo:myorg") shouldBe "cl100k_base"
    Registry.modelToEncoding("ft:davinci-002:myorg") shouldBe "cl100k_base"
    Registry.modelToEncoding("ft:babbage-002:myorg") shouldBe "cl100k_base"
  }

  test("modelToEncoding throws UnknownModelException for unknown model") {
    an [UnknownModelException] should be thrownBy {
      Registry.modelToEncoding("completely-unknown-model")
    }
  }

  /* ── Chat template tests ─────────────────────────────────────── */

  test("resolveChatTemplate returns correct template for TurbotokenV1") {
    val template = Chat.resolveChatTemplate(TurbotokenV1)
    template.messagePrefix shouldBe "<|im_start|>"
    template.messageSuffix shouldBe "<|im_end|>\n"
    template.assistantPrefix shouldBe Some("<|im_start|>assistant\n")
  }

  test("resolveChatTemplate returns correct template for ImTokens") {
    val template = Chat.resolveChatTemplate(ImTokens)
    template.messagePrefix shouldBe "<|im_start|>"
    template.messageSuffix shouldBe "<|im_end|>\n"
    template.assistantPrefix shouldBe Some("<|im_start|>assistant\n")
  }

  test("formatMessages formats messages correctly") {
    val messages = Seq(
      ChatMessage("user", content = "hello"),
      ChatMessage("assistant", content = "hi there")
    )
    val formatted = Chat.formatMessages(messages, ChatOptions())
    formatted should include("<|im_start|>user\nhello<|im_end|>")
    formatted should include("<|im_start|>assistant\nhi there<|im_end|>")
    formatted should endWith("<|im_start|>assistant\n")
  }

  test("formatMessages includes name when present") {
    val messages = Seq(
      ChatMessage("user", name = Some("alice"), content = "hello")
    )
    val formatted = Chat.formatMessages(messages, ChatOptions())
    formatted should include("user name=alice")
  }

  test("formatMessages omits assistant prime when primeWithAssistantResponse is None") {
    val messages = Seq(
      ChatMessage("user", content = "hello")
    )
    val formatted = Chat.formatMessages(messages, ChatOptions(primeWithAssistantResponse = None))
    formatted should not endWith "<|im_start|>assistant\n"
  }
}
