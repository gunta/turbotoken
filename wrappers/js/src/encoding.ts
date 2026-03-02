import { getEncodingSpec, type EncodingSpec } from "./registry";
import { loadWasm, type WasmBridge, type WasmLoadOptions } from "./wasm-loader";
import { loadNative, type NativeBridge, type NativeLoadOptions } from "./native-loader";

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const rankPayloadCache = new Map<string, Promise<Uint8Array>>();

export interface EncodingOptions {
  wasm?: WasmLoadOptions;
  native?: NativeLoadOptions;
  rankPayload?: Uint8Array;
  rankUrlOverride?: string;
  enableWasmBpe?: boolean;
  eagerLoad?: boolean;
  backend?: BackendMode;
}

export type BackendMode = "auto" | "native" | "wasm" | "js";
type BackendKind = "native" | "wasm" | "js";
type TokenBridge = WasmBridge | NativeBridge;

export interface ChatMessage {
  role?: string;
  name?: string;
  content?: string;
}

export interface ChatTemplate {
  messagePrefix: string;
  messageSuffix: string;
  assistantPrefix?: string | null;
}

export type ChatTemplateMode = "turbotoken_v1" | "im_tokens";

export interface ChatOptions {
  primeWithAssistantResponse?: string | null;
  template?: ChatTemplateMode | ChatTemplate;
}

function formatChatRole(templatePart: string, role: string): string {
  return templatePart.split("{role}").join(role);
}

function resolveChatTemplate(template: ChatTemplateMode | ChatTemplate | undefined): ChatTemplate {
  if (template === undefined || template === "turbotoken_v1") {
    return {
      messagePrefix: "[[role:{role}]]\n",
      messageSuffix: "\n[[/message]]\n",
      assistantPrefix: "[[role:{role}]]\n",
    };
  }
  if (template === "im_tokens") {
    return {
      messagePrefix: "<|im_start|>{role}\n",
      messageSuffix: "<|im_end|>\n",
      assistantPrefix: "<|im_start|>{role}\n",
    };
  }
  if (typeof template.messagePrefix !== "string" || template.messagePrefix.length === 0) {
    throw new Error("chat template requires non-empty messagePrefix");
  }
  if (typeof template.messageSuffix !== "string") {
    throw new Error("chat template requires string messageSuffix");
  }
  if (template.assistantPrefix != null && typeof template.assistantPrefix !== "string") {
    throw new Error("chat template assistantPrefix must be string or null");
  }
  return {
    messagePrefix: template.messagePrefix,
    messageSuffix: template.messageSuffix,
    assistantPrefix: template.assistantPrefix ?? null,
  };
}

async function fetchRankPayload(url: string): Promise<Uint8Array> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch rank payload from ${url}: HTTP ${response.status}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

function cachedRankPayload(url: string): Promise<Uint8Array> {
  const cached = rankPayloadCache.get(url);
  if (cached !== undefined) {
    return cached;
  }
  const pending = fetchRankPayload(url);
  rankPayloadCache.set(url, pending);
  return pending;
}

function decodeByteFallback(tokens: readonly number[]): string {
  const bytes = new Uint8Array(tokens.length);
  for (let i = 0; i < tokens.length; i += 1) {
    bytes[i] = tokens[i] & 0xff;
  }
  return decoder.decode(bytes);
}

function encodeByteFallback(text: string): number[] {
  return Array.from(encoder.encode(text));
}

function resolveBackendMode(explicit: BackendMode | undefined): BackendMode {
  if (explicit) {
    return explicit;
  }
  if (typeof process === "undefined") {
    return "auto";
  }
  const raw = (process.env.TURBOTOKEN_BACKEND ?? "").trim().toLowerCase();
  switch (raw) {
    case "native":
    case "wasm":
    case "js":
    case "auto":
      return raw;
    default:
      return "auto";
  }
}

async function readUtf8File(path: string): Promise<string> {
  if (typeof Bun !== "undefined") {
    return Bun.file(path).text();
  }
  const fs = await import("node:fs/promises");
  return fs.readFile(path, "utf8");
}

export class Encoding {
  private readonly spec: EncodingSpec;
  private readonly wasmOptions: WasmLoadOptions;
  private readonly nativeOptions: NativeLoadOptions;
  private readonly rankUrlOverride?: string;
  private readonly enableWasmBpe: boolean;
  private readonly backendMode: BackendMode;

  private bridge: TokenBridge | null = null;
  private rankPayload: Uint8Array | null = null;
  private loadPromise: Promise<void> | null = null;

  private encodeBytePath(text: string): number[] {
    if (this.bridge !== null) {
      return this.bridge.encodeUtf8Bytes(text);
    }
    return encodeByteFallback(text);
  }

  private decodeBytePath(tokens: readonly number[]): string {
    if (this.bridge !== null && tokens.every((token) => Number.isInteger(token) && token >= 0 && token <= 0xff)) {
      return decoder.decode(this.bridge.decodeUtf8Bytes(tokens));
    }
    return decodeByteFallback(tokens);
  }

  private countBytePath(text: string): number {
    return this.encodeBytePath(text).length;
  }

  constructor(public readonly name: string, options: EncodingOptions = {}) {
    this.spec = getEncodingSpec(name);
    this.wasmOptions = options.wasm ?? {};
    this.nativeOptions = options.native ?? {};
    this.rankUrlOverride = options.rankUrlOverride;
    this.rankPayload = options.rankPayload ?? null;
    this.enableWasmBpe = options.enableWasmBpe ?? false;
    this.backendMode = resolveBackendMode(options.backend);
    if (this.backendMode === "js" && this.enableWasmBpe) {
      throw new Error("backend='js' does not support BPE mode; use backend='wasm', 'native', or 'auto'");
    }

    if (options.eagerLoad) {
      void this.ready();
    }
  }

  static async create(name: string, options: EncodingOptions = {}): Promise<Encoding> {
    const enc = new Encoding(name, options);
    await enc.ready();
    return enc;
  }

  isReady(): boolean {
    if (this.backendMode === "js") {
      return !this.enableWasmBpe;
    }
    if (!this.enableWasmBpe) {
      return this.bridge !== null;
    }
    return this.bridge !== null && this.rankPayload !== null;
  }

  backendKind(): BackendKind {
    if (this.bridge === null) {
      return "js";
    }
    return this.bridge.kind;
  }

  async ready(): Promise<void> {
    if (this.isReady()) {
      return;
    }
    if (this.loadPromise === null) {
      this.loadPromise = this.load();
    }
    await this.loadPromise;
  }

  private async load(): Promise<void> {
    if (this.backendMode === "js") {
      this.bridge = null;
      this.rankPayload = null;
      return;
    }

    let bridge: TokenBridge | null = null;
    if (this.backendMode === "native" || this.backendMode === "auto") {
      try {
        bridge = await loadNative(this.nativeOptions);
      } catch (error) {
        if (this.backendMode === "native") {
          throw new Error(`native backend requested but unavailable: ${String(error)}`);
        }
      }
    }
    if (bridge === null) {
      bridge = await loadWasm(this.wasmOptions);
    }

    const rankPromise: Promise<Uint8Array | null> = this.enableWasmBpe
      ? this.rankPayload !== null
        ? Promise.resolve(this.rankPayload)
        : cachedRankPayload(this.rankUrlOverride ?? this.spec.rankFileUrl)
      : Promise.resolve(this.rankPayload);

    const rankPayload = await rankPromise;
    this.bridge = bridge;
    this.rankPayload = rankPayload;
  }

  encode(text: string): number[] {
    if (!this.enableWasmBpe) {
      return this.encodeBytePath(text);
    }
    if (!this.isReady()) {
      return encodeByteFallback(text);
    }
    return this.bridge!.encodeBpeFromRanks(this.rankPayload!, text);
  }

  async encodeAsync(text: string): Promise<number[]> {
    await this.ready();
    if (!this.enableWasmBpe) {
      return this.encodeBytePath(text);
    }
    return this.bridge!.encodeBpeFromRanks(this.rankPayload!, text);
  }

  decode(tokens: readonly number[]): string {
    if (!this.enableWasmBpe) {
      return this.decodeBytePath(tokens);
    }
    if (!this.isReady()) {
      return decodeByteFallback(tokens);
    }
    const bytes = this.bridge!.decodeBpeFromRanks(this.rankPayload!, tokens);
    return decoder.decode(bytes);
  }

  async decodeAsync(tokens: readonly number[]): Promise<string> {
    await this.ready();
    if (!this.enableWasmBpe) {
      return this.decodeBytePath(tokens);
    }
    const bytes = this.bridge!.decodeBpeFromRanks(this.rankPayload!, tokens);
    return decoder.decode(bytes);
  }

  count(text: string): number {
    if (!this.enableWasmBpe) {
      return this.countBytePath(text);
    }
    if (!this.isReady()) {
      return encodeByteFallback(text).length;
    }
    return this.bridge!.countBpeFromRanks(this.rankPayload!, text);
  }

  countTokens(text: string): number {
    return this.count(text);
  }

  isWithinTokenLimit(text: string, tokenLimit: number): number | false {
    if (tokenLimit < 0) {
      throw new Error("tokenLimit must be >= 0");
    }
    if (!this.enableWasmBpe) {
      const count = this.countBytePath(text);
      return count <= tokenLimit ? count : false;
    }
    if (!this.isReady()) {
      const count = encodeByteFallback(text).length;
      return count <= tokenLimit ? count : false;
    }
    return this.bridge!.isWithinTokenLimitBpeFromRanks(this.rankPayload!, text, tokenLimit);
  }

  async isWithinTokenLimitAsync(text: string, tokenLimit: number): Promise<number | false> {
    await this.ready();
    return this.isWithinTokenLimit(text, tokenLimit);
  }

  *encodeGenerator(text: string): Generator<number[], void, undefined> {
    yield this.encode(text);
  }

  *decodeGenerator(tokens: readonly number[]): Generator<string, void, undefined> {
    yield this.decode(tokens);
  }

  private *chatSegments(
    messages: Iterable<ChatMessage>,
    options: ChatOptions = {},
  ): Generator<string, void, undefined> {
    const template = resolveChatTemplate(options.template);
    for (const message of messages) {
      const roleValue = typeof message.name === "string" && message.name.length > 0
        ? message.name
        : typeof message.role === "string" && message.role.length > 0
          ? message.role
          : "user";
      const content = typeof message.content === "string" ? message.content : "";

      yield formatChatRole(template.messagePrefix, roleValue);
      if (content.length > 0) {
        yield content;
      }
      yield template.messageSuffix;
    }

    const prime = options.primeWithAssistantResponse ?? "assistant";
    if (typeof prime === "string" && prime.length > 0 && template.assistantPrefix) {
      yield formatChatRole(template.assistantPrefix, prime);
    }
  }

  encodeChat(messages: Iterable<ChatMessage>, options: ChatOptions = {}): number[] {
    const out: number[] = [];
    for (const chunk of this.encodeChatGenerator(messages, options)) {
      out.push(...chunk);
    }
    return out;
  }

  *encodeChatGenerator(
    messages: Iterable<ChatMessage>,
    options: ChatOptions = {},
  ): Generator<number[], void, undefined> {
    for (const segment of this.chatSegments(messages, options)) {
      yield this.encode(segment);
    }
  }

  countChat(messages: Iterable<ChatMessage>, options: ChatOptions = {}): number {
    let total = 0;
    for (const segment of this.chatSegments(messages, options)) {
      total += this.count(segment);
    }
    return total;
  }

  countChatTokens(messages: Iterable<ChatMessage>, options: ChatOptions = {}): number {
    return this.countChat(messages, options);
  }

  isChatWithinTokenLimit(
    messages: Iterable<ChatMessage>,
    tokenLimit: number,
    options: ChatOptions = {},
  ): number | false {
    if (tokenLimit < 0) {
      throw new Error("tokenLimit must be >= 0");
    }

    let total = 0;
    for (const segment of this.chatSegments(messages, options)) {
      const within = this.isWithinTokenLimit(segment, tokenLimit - total);
      if (within === false) {
        return false;
      }
      total += within;
      if (total > tokenLimit) {
        return false;
      }
    }
    return total;
  }

  async countAsync(text: string): Promise<number> {
    await this.ready();
    if (!this.enableWasmBpe) {
      return this.countBytePath(text);
    }
    return this.bridge!.countBpeFromRanks(this.rankPayload!, text);
  }

  async encodeFilePath(path: string): Promise<number[]> {
    const text = await readUtf8File(path);
    return this.encodeAsync(text);
  }

  async countFilePath(path: string): Promise<number> {
    const text = await readUtf8File(path);
    return this.countAsync(text);
  }

  async isFilePathWithinTokenLimit(path: string, tokenLimit: number): Promise<number | false> {
    const text = await readUtf8File(path);
    return this.isWithinTokenLimitAsync(text, tokenLimit);
  }
}
