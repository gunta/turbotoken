import { Encoding } from "./encoding";

export function getEncoding(name: string): Encoding {
  return new Encoding(name);
}

export function encodingForModel(model: string): Encoding {
  return new Encoding(model.includes("gpt") ? "o200k_base" : "cl100k_base");
}
