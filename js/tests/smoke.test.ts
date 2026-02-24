import { expect, test } from "bun:test";
import { getEncoding } from "../src/index";
import { encodingForModel } from "../src/index";

test("encoding roundtrip works with placeholder byte tokenizer", () => {
  const enc = getEncoding("o200k_base");
  const input = "hello";
  expect(enc.decode(enc.encode(input))).toBe(input);
});

test("model helper maps GPT models", () => {
  const enc = encodingForModel("gpt-4o");
  expect(enc.name).toBe("o200k_base");
});
