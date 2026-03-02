import TurboTokenModule from "./NativeTurboToken";
import { getEncodingSpec, type EncodingSpec } from "./registry";
import { cachedFetchRankBase64 } from "./rank_cache";
import {
  chatSegments,
  type ChatMessage,
  type ChatOptions,
} from "./chat";

export class Encoding {
  readonly name: string;
  private readonly spec: EncodingSpec;
  private rankBase64: string | null = null;
  private loadPromise: Promise<void> | null = null;

  constructor(name: string) {
    this.name = name;
    this.spec = getEncodingSpec(name);
  }

  private async ensureRanks(): Promise<string> {
    if (this.rankBase64 !== null) return this.rankBase64;
    if (this.loadPromise === null) {
      this.loadPromise = cachedFetchRankBase64(
        this.name,
        this.spec.rankFileUrl
      ).then((base64) => {
        this.rankBase64 = base64;
      });
    }
    await this.loadPromise;
    return this.rankBase64!;
  }

  async encode(text: string): Promise<number[]> {
    const ranks = await this.ensureRanks();
    return TurboTokenModule.encodeBpe(ranks, text);
  }

  async decode(tokens: number[]): Promise<string> {
    const ranks = await this.ensureRanks();
    return TurboTokenModule.decodeBpe(ranks, tokens);
  }

  async count(text: string): Promise<number> {
    const ranks = await this.ensureRanks();
    return TurboTokenModule.countBpe(ranks, text);
  }

  async countTokens(text: string): Promise<number> {
    return this.count(text);
  }

  async isWithinTokenLimit(
    text: string,
    tokenLimit: number
  ): Promise<number | false> {
    if (tokenLimit < 0) {
      throw new Error("tokenLimit must be >= 0");
    }
    const ranks = await this.ensureRanks();
    const result = await TurboTokenModule.isWithinTokenLimit(
      ranks,
      text,
      tokenLimit
    );
    // Native returns -2 when limit exceeded, token count otherwise
    return result < 0 ? false : result;
  }

  async encodeChat(
    messages: Iterable<ChatMessage>,
    options: ChatOptions = {}
  ): Promise<number[]> {
    const ranks = await this.ensureRanks();
    const out: number[] = [];
    for (const segment of chatSegments(messages, options)) {
      const tokens = await TurboTokenModule.encodeBpe(ranks, segment);
      out.push(...tokens);
    }
    return out;
  }

  async countChat(
    messages: Iterable<ChatMessage>,
    options: ChatOptions = {}
  ): Promise<number> {
    const ranks = await this.ensureRanks();
    let total = 0;
    for (const segment of chatSegments(messages, options)) {
      total += await TurboTokenModule.countBpe(ranks, segment);
    }
    return total;
  }

  async isChatWithinTokenLimit(
    messages: Iterable<ChatMessage>,
    tokenLimit: number,
    options: ChatOptions = {}
  ): Promise<number | false> {
    if (tokenLimit < 0) {
      throw new Error("tokenLimit must be >= 0");
    }
    const ranks = await this.ensureRanks();
    let total = 0;
    for (const segment of chatSegments(messages, options)) {
      const result = await TurboTokenModule.isWithinTokenLimit(
        ranks,
        segment,
        tokenLimit - total
      );
      if (result < 0) return false;
      total += result;
      if (total > tokenLimit) return false;
    }
    return total;
  }

  async encodeFilePath(filePath: string): Promise<number[]> {
    const ranks = await this.ensureRanks();
    return TurboTokenModule.encodeBpeFile(ranks, filePath);
  }

  async countFilePath(filePath: string): Promise<number> {
    const ranks = await this.ensureRanks();
    return TurboTokenModule.countBpeFile(ranks, filePath);
  }

  async isFilePathWithinTokenLimit(
    filePath: string,
    tokenLimit: number
  ): Promise<number | false> {
    if (tokenLimit < 0) {
      throw new Error("tokenLimit must be >= 0");
    }
    const count = await this.countFilePath(filePath);
    return count <= tokenLimit ? count : false;
  }
}
