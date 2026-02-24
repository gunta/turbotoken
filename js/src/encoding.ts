export class Encoding {
  constructor(public readonly name: string) {}

  encode(text: string): number[] {
    return Array.from(new TextEncoder().encode(text));
  }

  decode(tokens: number[]): string {
    return new TextDecoder().decode(new Uint8Array(tokens));
  }

  count(text: string): number {
    return this.encode(text).length;
  }
}
