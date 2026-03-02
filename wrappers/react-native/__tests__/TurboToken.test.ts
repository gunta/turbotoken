import {
  getEncodingSpec,
  modelToEncoding,
  listEncodingNames,
} from "../src/registry";
import { resolveChatTemplate, chatSegments } from "../src/chat";

describe("registry", () => {
  test("listEncodingNames returns all 7 encodings sorted", () => {
    const names = listEncodingNames();
    expect(names).toEqual([
      "cl100k_base",
      "gpt2",
      "o200k_base",
      "o200k_harmony",
      "p50k_base",
      "p50k_edit",
      "r50k_base",
    ]);
  });

  test("getEncodingSpec returns correct spec for o200k_base", () => {
    const spec = getEncodingSpec("o200k_base");
    expect(spec.name).toBe("o200k_base");
    expect(spec.explicitNVocab).toBe(200019);
    expect(spec.specialTokens["<|endoftext|>"]).toBe(199999);
    expect(spec.rankFileUrl).toContain("o200k_base.tiktoken");
  });

  test("getEncodingSpec returns correct spec for cl100k_base", () => {
    const spec = getEncodingSpec("cl100k_base");
    expect(spec.name).toBe("cl100k_base");
    expect(spec.explicitNVocab).toBe(100277);
    expect(spec.specialTokens["<|endoftext|>"]).toBe(100257);
    expect(spec.specialTokens["<|fim_prefix|>"]).toBe(100258);
  });

  test("getEncodingSpec throws for unknown encoding", () => {
    expect(() => getEncodingSpec("nonexistent")).toThrow(
      "Unknown encoding 'nonexistent'"
    );
  });

  test("modelToEncoding maps exact model names", () => {
    expect(modelToEncoding("gpt-4o")).toBe("o200k_base");
    expect(modelToEncoding("gpt-4")).toBe("cl100k_base");
    expect(modelToEncoding("gpt-3.5-turbo")).toBe("cl100k_base");
    expect(modelToEncoding("text-davinci-003")).toBe("p50k_base");
    expect(modelToEncoding("davinci")).toBe("r50k_base");
    expect(modelToEncoding("gpt2")).toBe("gpt2");
    expect(modelToEncoding("o1")).toBe("o200k_base");
    expect(modelToEncoding("o3")).toBe("o200k_base");
    expect(modelToEncoding("gpt-5")).toBe("o200k_base");
    expect(modelToEncoding("gpt-4.1")).toBe("o200k_base");
    expect(modelToEncoding("gpt-oss-120b")).toBe("o200k_harmony");
  });

  test("modelToEncoding maps prefix model names", () => {
    expect(modelToEncoding("gpt-4o-2024-01-01")).toBe("o200k_base");
    expect(modelToEncoding("gpt-4-turbo-preview")).toBe("cl100k_base");
    expect(modelToEncoding("gpt-3.5-turbo-16k")).toBe("cl100k_base");
    expect(modelToEncoding("o1-preview")).toBe("o200k_base");
    expect(modelToEncoding("o3-mini")).toBe("o200k_base");
    expect(modelToEncoding("ft:gpt-4o:my-org")).toBe("o200k_base");
    expect(modelToEncoding("ft:gpt-4:my-org")).toBe("cl100k_base");
    expect(modelToEncoding("gpt-oss-7b")).toBe("o200k_harmony");
  });

  test("modelToEncoding throws for unknown model", () => {
    expect(() => modelToEncoding("unknown-model-xyz")).toThrow(
      "Could not automatically map"
    );
  });

  test("all encoding specs have required fields", () => {
    for (const name of listEncodingNames()) {
      const spec = getEncodingSpec(name);
      expect(spec.name).toBe(name);
      expect(typeof spec.rankFileUrl).toBe("string");
      expect(spec.rankFileUrl.length).toBeGreaterThan(0);
      expect(typeof spec.patStr).toBe("string");
      expect(spec.patStr.length).toBeGreaterThan(0);
      expect(typeof spec.explicitNVocab).toBe("number");
      expect(spec.explicitNVocab).toBeGreaterThan(0);
      expect(spec.specialTokens["<|endoftext|>"]).toBeDefined();
    }
  });
});

describe("chat", () => {
  test("resolveChatTemplate returns default turbotoken_v1", () => {
    const tpl = resolveChatTemplate(undefined);
    expect(tpl.messagePrefix).toBe("[[role:{role}]]\n");
    expect(tpl.messageSuffix).toBe("\n[[/message]]\n");
    expect(tpl.assistantPrefix).toBe("[[role:{role}]]\n");
  });

  test("resolveChatTemplate returns turbotoken_v1 explicitly", () => {
    const tpl = resolveChatTemplate("turbotoken_v1");
    expect(tpl.messagePrefix).toBe("[[role:{role}]]\n");
  });

  test("resolveChatTemplate returns im_tokens template", () => {
    const tpl = resolveChatTemplate("im_tokens");
    expect(tpl.messagePrefix).toBe("<|im_start|>{role}\n");
    expect(tpl.messageSuffix).toBe("<|im_end|>\n");
    expect(tpl.assistantPrefix).toBe("<|im_start|>{role}\n");
  });

  test("resolveChatTemplate accepts custom template", () => {
    const tpl = resolveChatTemplate({
      messagePrefix: "[{role}]: ",
      messageSuffix: "\n",
      assistantPrefix: "[assistant]: ",
    });
    expect(tpl.messagePrefix).toBe("[{role}]: ");
    expect(tpl.messageSuffix).toBe("\n");
    expect(tpl.assistantPrefix).toBe("[assistant]: ");
  });

  test("resolveChatTemplate rejects empty messagePrefix", () => {
    expect(() =>
      resolveChatTemplate({
        messagePrefix: "",
        messageSuffix: "\n",
      })
    ).toThrow("non-empty messagePrefix");
  });

  test("chatSegments produces correct segments for messages", () => {
    const messages = [
      { role: "system", content: "You are helpful." },
      { role: "user", content: "Hello!" },
    ];
    const segments = [...chatSegments(messages)];
    expect(segments).toEqual([
      "[[role:system]]\n",
      "You are helpful.",
      "\n[[/message]]\n",
      "[[role:user]]\n",
      "Hello!",
      "\n[[/message]]\n",
      "[[role:assistant]]\n",
    ]);
  });

  test("chatSegments uses name over role", () => {
    const messages = [{ role: "user", name: "Alice", content: "Hi" }];
    const segments = [...chatSegments(messages)];
    expect(segments[0]).toBe("[[role:Alice]]\n");
  });

  test("chatSegments defaults role to user", () => {
    const messages = [{ content: "Hi" }];
    const segments = [...chatSegments(messages)];
    expect(segments[0]).toBe("[[role:user]]\n");
  });

  test("chatSegments skips empty content", () => {
    const messages = [{ role: "user", content: "" }];
    const segments = [...chatSegments(messages)];
    // prefix, suffix, assistant prefix -- no content segment
    expect(segments).toEqual([
      "[[role:user]]\n",
      "\n[[/message]]\n",
      "[[role:assistant]]\n",
    ]);
  });

  test("chatSegments with im_tokens template", () => {
    const messages = [{ role: "user", content: "test" }];
    const segments = [
      ...chatSegments(messages, { template: "im_tokens" }),
    ];
    expect(segments[0]).toBe("<|im_start|>user\n");
    expect(segments[2]).toBe("<|im_end|>\n");
  });

  test("chatSegments with custom prime response", () => {
    const messages = [{ role: "user", content: "Hi" }];
    const segments = [
      ...chatSegments(messages, {
        primeWithAssistantResponse: "bot",
      }),
    ];
    const last = segments[segments.length - 1];
    expect(last).toBe("[[role:bot]]\n");
  });

  test("chatSegments with null prime response omits assistant", () => {
    const messages = [{ role: "user", content: "Hi" }];
    const segments = [
      ...chatSegments(messages, {
        primeWithAssistantResponse: null,
      }),
    ];
    // Should not have assistant prefix at end
    expect(segments).toEqual([
      "[[role:user]]\n",
      "Hi",
      "\n[[/message]]\n",
    ]);
  });
});
