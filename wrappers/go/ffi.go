package turbotoken

/*
#cgo LDFLAGS: -lturbotoken
#cgo CFLAGS: -I../include
#include "turbotoken.h"
#include <stdlib.h>
*/
import "C"
import "unsafe"

// ffiVersion returns the turbotoken library version string.
func ffiVersion() string {
	return C.GoString(C.turbotoken_version())
}

// ffiEncodeBPE encodes text into BPE tokens using the provided rank data.
// Uses the two-pass pattern: first call with nil output to get size, then allocate and call again.
func ffiEncodeBPE(rankBytes []byte, text []byte) ([]uint32, error) {
	if len(text) == 0 {
		return nil, nil
	}

	rankPtr := (*C.uint8_t)(unsafe.Pointer(&rankBytes[0]))
	rankLen := C.size_t(len(rankBytes))
	textPtr := (*C.uint8_t)(unsafe.Pointer(&text[0]))
	textLen := C.size_t(len(text))

	// Pass 1: query size.
	n := C.turbotoken_encode_bpe_from_ranks(rankPtr, rankLen, textPtr, textLen, nil, 0)
	if n < 0 {
		return nil, nativeError("encode_bpe")
	}
	if n == 0 {
		return nil, nil
	}

	// Pass 2: fill output buffer.
	out := make([]uint32, int(n))
	outPtr := (*C.uint32_t)(unsafe.Pointer(&out[0]))
	n2 := C.turbotoken_encode_bpe_from_ranks(rankPtr, rankLen, textPtr, textLen, outPtr, C.size_t(n))
	if n2 < 0 {
		return nil, nativeError("encode_bpe")
	}
	return out[:int(n2)], nil
}

// ffiDecodeBPE decodes BPE tokens back to UTF-8 bytes using the provided rank data.
func ffiDecodeBPE(rankBytes []byte, tokens []uint32) ([]byte, error) {
	if len(tokens) == 0 {
		return nil, nil
	}

	rankPtr := (*C.uint8_t)(unsafe.Pointer(&rankBytes[0]))
	rankLen := C.size_t(len(rankBytes))
	tokPtr := (*C.uint32_t)(unsafe.Pointer(&tokens[0]))
	tokLen := C.size_t(len(tokens))

	// Pass 1: query size.
	n := C.turbotoken_decode_bpe_from_ranks(rankPtr, rankLen, tokPtr, tokLen, nil, 0)
	if n < 0 {
		return nil, nativeError("decode_bpe")
	}
	if n == 0 {
		return nil, nil
	}

	// Pass 2: fill output buffer.
	out := make([]byte, int(n))
	outPtr := (*C.uint8_t)(unsafe.Pointer(&out[0]))
	n2 := C.turbotoken_decode_bpe_from_ranks(rankPtr, rankLen, tokPtr, tokLen, outPtr, C.size_t(n))
	if n2 < 0 {
		return nil, nativeError("decode_bpe")
	}
	return out[:int(n2)], nil
}

// ffiCountBPE counts BPE tokens for text without materializing the token array.
func ffiCountBPE(rankBytes []byte, text []byte) (int, error) {
	if len(text) == 0 {
		return 0, nil
	}

	rankPtr := (*C.uint8_t)(unsafe.Pointer(&rankBytes[0]))
	rankLen := C.size_t(len(rankBytes))
	textPtr := (*C.uint8_t)(unsafe.Pointer(&text[0]))
	textLen := C.size_t(len(text))

	n := C.turbotoken_count_bpe_from_ranks(rankPtr, rankLen, textPtr, textLen)
	if n < 0 {
		return 0, nativeError("count_bpe")
	}
	return int(n), nil
}

// ffiIsWithinTokenLimit checks if text is within a token limit.
// Returns (count, true, nil) if within limit, (0, false, nil) if exceeded.
func ffiIsWithinTokenLimit(rankBytes []byte, text []byte, limit int) (int, bool, error) {
	if len(text) == 0 {
		return 0, true, nil
	}

	rankPtr := (*C.uint8_t)(unsafe.Pointer(&rankBytes[0]))
	rankLen := C.size_t(len(rankBytes))
	textPtr := (*C.uint8_t)(unsafe.Pointer(&text[0]))
	textLen := C.size_t(len(text))

	n := C.turbotoken_is_within_token_limit_bpe_from_ranks(
		rankPtr, rankLen, textPtr, textLen, C.size_t(limit),
	)
	if n == -1 {
		return 0, false, nativeError("is_within_token_limit")
	}
	if n == -2 {
		return 0, false, nil
	}
	return int(n), true, nil
}

// ffiEncodeBPEFile encodes a file's contents into BPE tokens.
func ffiEncodeBPEFile(rankBytes []byte, filePath string) ([]uint32, error) {
	pathBytes := []byte(filePath)
	if len(pathBytes) == 0 {
		return nil, nativeError("encode_bpe_file: empty path")
	}

	rankPtr := (*C.uint8_t)(unsafe.Pointer(&rankBytes[0]))
	rankLen := C.size_t(len(rankBytes))
	pathPtr := (*C.uint8_t)(unsafe.Pointer(&pathBytes[0]))
	pathLen := C.size_t(len(pathBytes))

	// Pass 1: query size.
	n := C.turbotoken_encode_bpe_file_from_ranks(rankPtr, rankLen, pathPtr, pathLen, nil, 0)
	if n < 0 {
		return nil, nativeError("encode_bpe_file")
	}
	if n == 0 {
		return nil, nil
	}

	// Pass 2: fill output buffer.
	out := make([]uint32, int(n))
	outPtr := (*C.uint32_t)(unsafe.Pointer(&out[0]))
	n2 := C.turbotoken_encode_bpe_file_from_ranks(rankPtr, rankLen, pathPtr, pathLen, outPtr, C.size_t(n))
	if n2 < 0 {
		return nil, nativeError("encode_bpe_file")
	}
	return out[:int(n2)], nil
}

// ffiCountBPEFile counts BPE tokens in a file without materializing the token array.
func ffiCountBPEFile(rankBytes []byte, filePath string) (int, error) {
	pathBytes := []byte(filePath)
	if len(pathBytes) == 0 {
		return 0, nativeError("count_bpe_file: empty path")
	}

	rankPtr := (*C.uint8_t)(unsafe.Pointer(&rankBytes[0]))
	rankLen := C.size_t(len(rankBytes))
	pathPtr := (*C.uint8_t)(unsafe.Pointer(&pathBytes[0]))
	pathLen := C.size_t(len(pathBytes))

	n := C.turbotoken_count_bpe_file_from_ranks(rankPtr, rankLen, pathPtr, pathLen)
	if n < 0 {
		return 0, nativeError("count_bpe_file")
	}
	return int(n), nil
}
