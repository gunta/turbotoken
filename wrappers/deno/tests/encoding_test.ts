import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  getEncodingSpec,
  listEncodingNames,
  modelToEncoding,
} from "../registry.ts";
import { formatChat, resolveChatTemplate } from "../chat.ts";
import type { ChatMessage } from "../chat.ts";

Deno.test("listEncodingNames returns 7 encodings", () => {
  const names = listEncodingNames();
  assertEquals(names.length, 7);
  assertEquals(names.includes("cl100k_base"), true);
  assertEquals(names.includes("o200k_base"), true);
  assertEquals(names.includes("r50k_base"), true);
  assertEquals(names.includes("p50k_base"), true);
  assertEquals(names.includes("gpt2"), true);
  assertEquals(names.includes("p50k_edit"), true);
  assertEquals(names.includes("o200k_harmony"), true);
});

Deno.test("getEncodingSpec returns correct spec", () => {
  const spec = getEncodingSpec("cl100k_base");
  assertEquals(spec.name, "cl100k_base");
  assertEquals(spec.nVocab, 100277);
  assertEquals(spec.specialTokens["<|endoftext|>"], 100257);
});

Deno.test("getEncodingSpec throws on unknown", () => {
  assertThrows(
    () => getEncodingSpec("nonexistent"),
    Error,
    "Unknown encoding",
  );
});

Deno.test("modelToEncoding resolves exact matches", () => {
  assertEquals(modelToEncoding("gpt-4o"), "o200k_base");
  assertEquals(modelToEncoding("gpt-4"), "cl100k_base");
  assertEquals(modelToEncoding("gpt-3.5-turbo"), "cl100k_base");
  assertEquals(modelToEncoding("davinci"), "r50k_base");
  assertEquals(modelToEncoding("gpt2"), "gpt2");
});

Deno.test("modelToEncoding resolves prefix matches", () => {
  assertEquals(modelToEncoding("gpt-4o-2024-01-01"), "o200k_base");
  assertEquals(modelToEncoding("gpt-4-turbo-preview"), "cl100k_base");
  assertEquals(modelToEncoding("o1-preview"), "o200k_base");
});

Deno.test("modelToEncoding throws on unknown model", () => {
  assertThrows(
    () => modelToEncoding("totally-unknown-model"),
    Error,
    "Could not automatically map",
  );
});

Deno.test("resolveChatTemplate turbotoken_v1", () => {
  const t = resolveChatTemplate("turbotoken_v1");
  assertEquals(t.messagePrefix, "<|im_start|>");
  assertEquals(t.messageSuffix, "<|im_end|>\n");
  assertEquals(t.assistantPrefix, "<|im_start|>assistant\n");
});

Deno.test("resolveChatTemplate im_tokens", () => {
  const t = resolveChatTemplate("im_tokens");
  assertEquals(t.messagePrefix, "");
  assertEquals(t.messageSuffix, "");
  assertEquals(t.assistantPrefix, undefined);
});

Deno.test("formatChat turbotoken_v1", () => {
  const messages: ChatMessage[] = [
    { role: "user", content: "Hello" },
  ];
  const result = formatChat(messages, { templateMode: "turbotoken_v1" });
  assertEquals(result, "<|im_start|>user\nHello<|im_end|>\n");
});

Deno.test("formatChat with name", () => {
  const messages: ChatMessage[] = [
    { role: "user", name: "Alice", content: "Hi" },
  ];
  const result = formatChat(messages, { templateMode: "turbotoken_v1" });
  assertEquals(result, "<|im_start|>user name=Alice\nHi<|im_end|>\n");
});

Deno.test("formatChat with assistant priming", () => {
  const messages: ChatMessage[] = [
    { role: "user", content: "Hello" },
  ];
  const result = formatChat(messages, {
    templateMode: "turbotoken_v1",
    primeWithAssistantResponse: true,
  });
  assertEquals(
    result,
    "<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n",
  );
});
