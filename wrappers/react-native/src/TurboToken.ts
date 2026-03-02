import { Encoding } from "./Encoding";
import TurboTokenModule from "./NativeTurboToken";
import {
  getEncodingSpec,
  modelToEncoding,
  listEncodingNames as listNames,
} from "./registry";

const encodingCache = new Map<string, Encoding>();

export class TurboToken {
  static getEncoding(name: string): Encoding {
    // Validate the name
    getEncodingSpec(name);
    const cached = encodingCache.get(name);
    if (cached) return cached;
    const enc = new Encoding(name);
    encodingCache.set(name, enc);
    return enc;
  }

  static getEncodingForModel(model: string): Encoding {
    const encodingName = modelToEncoding(model);
    return TurboToken.getEncoding(encodingName);
  }

  static listEncodingNames(): string[] {
    return listNames();
  }

  static version(): string {
    return TurboTokenModule.version();
  }
}
