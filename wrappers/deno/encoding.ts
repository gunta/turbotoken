import { lib, twoPassDecode, twoPassEncode } from "./ffi.ts";
import type { EncodingSpec } from "./registry.ts";
import type { ChatMessage, ChatOptions } from "./chat.ts";
import { formatChat } from "./chat.ts";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export class Encoding {
  readonly name: string;
  readonly spec: EncodingSpec;
  private readonly rankPayload: Uint8Array;

  constructor(name: string, spec: EncodingSpec, rankPayload: Uint8Array) {
    this.name = name;
    this.spec = spec;
    this.rankPayload = rankPayload;
  }

  encode(text: string): number[] {
    const textBytes = encoder.encode(text);
    const result = twoPassEncode(
      this.rankPayload,
      textBytes,
      (rp, rl, ip, il, op, oc) =>
        lib.symbols.turbotoken_encode_bpe_from_ranks(rp, rl, ip, il, op, oc),
    );
    return Array.from(result);
  }

  decode(tokens: number[]): string {
    const tokenBuf = new Uint32Array(tokens);
    const result = twoPassDecode(
      this.rankPayload,
      tokenBuf,
      (rp, rl, ip, il, op, oc) =>
        lib.symbols.turbotoken_decode_bpe_from_ranks(rp, rl, ip, il, op, oc),
    );
    return decoder.decode(result);
  }

  count(text: string): number {
    const textBytes = encoder.encode(text);
    const rankPtr = Deno.UnsafePointer.of(this.rankPayload)!;
    const textPtr = Deno.UnsafePointer.of(textBytes)!;
    const result = Number(
      lib.symbols.turbotoken_count_bpe_from_ranks(
        rankPtr,
        this.rankPayload.length,
        textPtr,
        textBytes.length,
      ),
    );
    if (result < 0) throw new Error(`count returned error code ${result}`);
    return result;
  }

  countTokens(text: string): number {
    return this.count(text);
  }

  isWithinTokenLimit(text: string, limit: number): number | false {
    const textBytes = encoder.encode(text);
    const rankPtr = Deno.UnsafePointer.of(this.rankPayload)!;
    const textPtr = Deno.UnsafePointer.of(textBytes)!;
    const result = Number(
      lib.symbols.turbotoken_is_within_token_limit_bpe_from_ranks(
        rankPtr,
        this.rankPayload.length,
        textPtr,
        textBytes.length,
        limit,
      ),
    );
    if (result === -2) return false;
    if (result < 0) {
      throw new Error(`isWithinTokenLimit returned error code ${result}`);
    }
    return result;
  }

  encodeChat(messages: ChatMessage[], options?: ChatOptions): number[] {
    const text = formatChat(messages, options);
    return this.encode(text);
  }

  countChat(messages: ChatMessage[], options?: ChatOptions): number {
    const text = formatChat(messages, options);
    return this.count(text);
  }

  isChatWithinTokenLimit(
    messages: ChatMessage[],
    limit: number,
    options?: ChatOptions,
  ): number | false {
    const text = formatChat(messages, options);
    return this.isWithinTokenLimit(text, limit);
  }

  encodeFilePath(path: string): number[] {
    const pathBytes = encoder.encode(path);
    const result = twoPassEncode(
      this.rankPayload,
      pathBytes,
      (rp, rl, ip, il, op, oc) =>
        lib.symbols.turbotoken_encode_bpe_file_from_ranks(
          rp,
          rl,
          ip,
          il,
          op,
          oc,
        ),
    );
    return Array.from(result);
  }

  countFilePath(path: string): number {
    const pathBytes = encoder.encode(path);
    const rankPtr = Deno.UnsafePointer.of(this.rankPayload)!;
    const pathPtr = Deno.UnsafePointer.of(pathBytes)!;
    const result = Number(
      lib.symbols.turbotoken_count_bpe_file_from_ranks(
        rankPtr,
        this.rankPayload.length,
        pathPtr,
        pathBytes.length,
      ),
    );
    if (result < 0) {
      throw new Error(`countFilePath returned error code ${result}`);
    }
    return result;
  }

  isFilePathWithinTokenLimit(path: string, limit: number): number | false {
    const pathBytes = encoder.encode(path);
    const rankPtr = Deno.UnsafePointer.of(this.rankPayload)!;
    const pathPtr = Deno.UnsafePointer.of(pathBytes)!;
    const result = Number(
      lib.symbols.turbotoken_is_within_token_limit_bpe_file_from_ranks(
        rankPtr,
        this.rankPayload.length,
        pathPtr,
        pathBytes.length,
        limit,
      ),
    );
    if (result === -2) return false;
    if (result < 0) {
      throw new Error(
        `isFilePathWithinTokenLimit returned error code ${result}`,
      );
    }
    return result;
  }
}
