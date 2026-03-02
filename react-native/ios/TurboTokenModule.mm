#import "TurboTokenModule.h"
#import <React/RCTLog.h>
#include "turbotoken.h"
#include <string>
#include <vector>

// Base64 decode helper
static NSData *decodeBase64(NSString *base64String) {
  return [[NSData alloc] initWithBase64EncodedString:base64String options:0];
}

@implementation TurboTokenModule

RCT_EXPORT_MODULE(TurboToken)

+ (BOOL)requiresMainQueueSetup {
  return NO;
}

- (dispatch_queue_t)methodQueue {
  return dispatch_queue_create("com.turbotoken.rn", DISPATCH_QUEUE_SERIAL);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(version) {
  const char *v = turbotoken_version();
  return [NSString stringWithUTF8String:v];
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(clearCache) {
  turbotoken_clear_rank_table_cache();
  return nil;
}

RCT_EXPORT_METHOD(encodeBpe:(NSString *)rankBase64
                  text:(NSString *)text
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @try {
      NSData *rankData = decodeBase64(rankBase64);
      if (!rankData) {
        reject(@"E_DECODE", @"Failed to decode rank base64", nil);
        return;
      }
      const uint8_t *rankBytes = (const uint8_t *)[rankData bytes];
      size_t rankLen = [rankData length];

      NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
      const uint8_t *textBytes = (const uint8_t *)[textData bytes];
      size_t textLen = [textData length];

      // First pass: get required size
      ptrdiff_t needed = turbotoken_encode_bpe_from_ranks(
        rankBytes, rankLen, textBytes, textLen, NULL, 0);
      if (needed < 0) {
        reject(@"E_ENCODE", @"BPE encode size query failed", nil);
        return;
      }

      // Second pass: encode
      std::vector<uint32_t> tokens(needed);
      ptrdiff_t written = turbotoken_encode_bpe_from_ranks(
        rankBytes, rankLen, textBytes, textLen, tokens.data(), tokens.size());
      if (written < 0) {
        reject(@"E_ENCODE", @"BPE encode failed", nil);
        return;
      }

      NSMutableArray *result = [NSMutableArray arrayWithCapacity:written];
      for (ptrdiff_t i = 0; i < written; i++) {
        [result addObject:@(tokens[i])];
      }
      resolve(result);
    } @catch (NSException *exception) {
      reject(@"E_ENCODE", exception.reason, nil);
    }
  });
}

RCT_EXPORT_METHOD(decodeBpe:(NSString *)rankBase64
                  tokens:(NSArray<NSNumber *> *)tokens
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @try {
      NSData *rankData = decodeBase64(rankBase64);
      if (!rankData) {
        reject(@"E_DECODE", @"Failed to decode rank base64", nil);
        return;
      }
      const uint8_t *rankBytes = (const uint8_t *)[rankData bytes];
      size_t rankLen = [rankData length];

      std::vector<uint32_t> tokenVec(tokens.count);
      for (NSUInteger i = 0; i < tokens.count; i++) {
        tokenVec[i] = [tokens[i] unsignedIntValue];
      }

      // First pass: get required size
      ptrdiff_t needed = turbotoken_decode_bpe_from_ranks(
        rankBytes, rankLen, tokenVec.data(), tokenVec.size(), NULL, 0);
      if (needed < 0) {
        reject(@"E_DECODE", @"BPE decode size query failed", nil);
        return;
      }

      // Second pass: decode
      std::vector<uint8_t> outBytes(needed);
      ptrdiff_t written = turbotoken_decode_bpe_from_ranks(
        rankBytes, rankLen, tokenVec.data(), tokenVec.size(),
        outBytes.data(), outBytes.size());
      if (written < 0) {
        reject(@"E_DECODE", @"BPE decode failed", nil);
        return;
      }

      NSString *result = [[NSString alloc]
        initWithBytes:outBytes.data()
        length:written
        encoding:NSUTF8StringEncoding];
      if (!result) {
        reject(@"E_DECODE", @"Failed to create UTF-8 string from decoded bytes", nil);
        return;
      }
      resolve(result);
    } @catch (NSException *exception) {
      reject(@"E_DECODE", exception.reason, nil);
    }
  });
}

RCT_EXPORT_METHOD(countBpe:(NSString *)rankBase64
                  text:(NSString *)text
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @try {
      NSData *rankData = decodeBase64(rankBase64);
      if (!rankData) {
        reject(@"E_DECODE", @"Failed to decode rank base64", nil);
        return;
      }
      const uint8_t *rankBytes = (const uint8_t *)[rankData bytes];
      size_t rankLen = [rankData length];

      NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
      const uint8_t *textBytes = (const uint8_t *)[textData bytes];
      size_t textLen = [textData length];

      ptrdiff_t count = turbotoken_count_bpe_from_ranks(
        rankBytes, rankLen, textBytes, textLen);
      if (count < 0) {
        reject(@"E_COUNT", @"BPE count failed", nil);
        return;
      }
      resolve(@(count));
    } @catch (NSException *exception) {
      reject(@"E_COUNT", exception.reason, nil);
    }
  });
}

RCT_EXPORT_METHOD(isWithinTokenLimit:(NSString *)rankBase64
                  text:(NSString *)text
                  limit:(double)limit
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @try {
      NSData *rankData = decodeBase64(rankBase64);
      if (!rankData) {
        reject(@"E_DECODE", @"Failed to decode rank base64", nil);
        return;
      }
      const uint8_t *rankBytes = (const uint8_t *)[rankData bytes];
      size_t rankLen = [rankData length];

      NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
      const uint8_t *textBytes = (const uint8_t *)[textData bytes];
      size_t textLen = [textData length];

      ptrdiff_t result = turbotoken_is_within_token_limit_bpe_from_ranks(
        rankBytes, rankLen, textBytes, textLen, (size_t)limit);
      // Returns count if within limit, -2 if exceeded, -1 on error
      if (result == -1) {
        reject(@"E_LIMIT", @"Token limit check failed", nil);
        return;
      }
      resolve(@(result));
    } @catch (NSException *exception) {
      reject(@"E_LIMIT", exception.reason, nil);
    }
  });
}

RCT_EXPORT_METHOD(encodeBpeFile:(NSString *)rankBase64
                  filePath:(NSString *)filePath
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @try {
      NSData *rankData = decodeBase64(rankBase64);
      if (!rankData) {
        reject(@"E_DECODE", @"Failed to decode rank base64", nil);
        return;
      }
      const uint8_t *rankBytes = (const uint8_t *)[rankData bytes];
      size_t rankLen = [rankData length];

      NSData *pathData = [filePath dataUsingEncoding:NSUTF8StringEncoding];
      const uint8_t *pathBytes = (const uint8_t *)[pathData bytes];
      size_t pathLen = [pathData length];

      // First pass: get size
      ptrdiff_t needed = turbotoken_encode_bpe_file_from_ranks(
        rankBytes, rankLen, pathBytes, pathLen, NULL, 0);
      if (needed < 0) {
        reject(@"E_ENCODE_FILE", @"BPE file encode size query failed", nil);
        return;
      }

      // Second pass: encode
      std::vector<uint32_t> tokens(needed);
      ptrdiff_t written = turbotoken_encode_bpe_file_from_ranks(
        rankBytes, rankLen, pathBytes, pathLen, tokens.data(), tokens.size());
      if (written < 0) {
        reject(@"E_ENCODE_FILE", @"BPE file encode failed", nil);
        return;
      }

      NSMutableArray *result = [NSMutableArray arrayWithCapacity:written];
      for (ptrdiff_t i = 0; i < written; i++) {
        [result addObject:@(tokens[i])];
      }
      resolve(result);
    } @catch (NSException *exception) {
      reject(@"E_ENCODE_FILE", exception.reason, nil);
    }
  });
}

RCT_EXPORT_METHOD(countBpeFile:(NSString *)rankBase64
                  filePath:(NSString *)filePath
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @try {
      NSData *rankData = decodeBase64(rankBase64);
      if (!rankData) {
        reject(@"E_DECODE", @"Failed to decode rank base64", nil);
        return;
      }
      const uint8_t *rankBytes = (const uint8_t *)[rankData bytes];
      size_t rankLen = [rankData length];

      NSData *pathData = [filePath dataUsingEncoding:NSUTF8StringEncoding];
      const uint8_t *pathBytes = (const uint8_t *)[pathData bytes];
      size_t pathLen = [pathData length];

      ptrdiff_t count = turbotoken_count_bpe_file_from_ranks(
        rankBytes, rankLen, pathBytes, pathLen);
      if (count < 0) {
        reject(@"E_COUNT_FILE", @"BPE file count failed", nil);
        return;
      }
      resolve(@(count));
    } @catch (NSException *exception) {
      reject(@"E_COUNT_FILE", exception.reason, nil);
    }
  });
}

@end
