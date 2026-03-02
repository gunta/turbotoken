import { NativeModules, Platform } from "react-native";

export interface NativeTurboTokenSpec {
  version(): string;
  clearCache(): void;
  encodeBpe(rankBase64: string, text: string): Promise<number[]>;
  decodeBpe(rankBase64: string, tokens: number[]): Promise<string>;
  countBpe(rankBase64: string, text: string): Promise<number>;
  isWithinTokenLimit(
    rankBase64: string,
    text: string,
    limit: number
  ): Promise<number>;
  encodeBpeFile(rankBase64: string, filePath: string): Promise<number[]>;
  countBpeFile(rankBase64: string, filePath: string): Promise<number>;
}

const LINKING_ERROR =
  `The package 'react-native-turbotoken' doesn't seem to be linked. Make sure:\n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: "" }) +
  "- You rebuilt the app after installing the package\n" +
  "- You are not using Expo Go\n";

const TurboTokenModule: NativeTurboTokenSpec = NativeModules.TurboToken
  ? NativeModules.TurboToken
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

export default TurboTokenModule;
