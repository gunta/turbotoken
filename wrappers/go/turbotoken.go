// Package turbotoken provides Go bindings for turbotoken, the fastest BPE tokenizer.
//
// It is a drop-in replacement for tiktoken with identical encoding output.
// The core is implemented in Zig with hand-written assembly for peak performance.
//
// Basic usage:
//
//	enc, err := turbotoken.GetEncoding("cl100k_base")
//	if err != nil { log.Fatal(err) }
//	tokens, err := enc.Encode("hello world")
//	if err != nil { log.Fatal(err) }
//	text, err := enc.Decode(tokens)
//	if err != nil { log.Fatal(err) }
package turbotoken

import "sync"

var (
	encodingCache   = make(map[string]*Encoding)
	encodingCacheMu sync.Mutex
)

// GetEncoding returns a ready-to-use Encoding for the given encoding name
// (e.g. "cl100k_base", "o200k_base"). The encoding is cached after first use.
func GetEncoding(name string) (*Encoding, error) {
	encodingCacheMu.Lock()
	defer encodingCacheMu.Unlock()

	if enc, ok := encodingCache[name]; ok {
		return enc, nil
	}

	spec, err := GetEncodingSpec(name)
	if err != nil {
		return nil, err
	}

	enc := newEncoding(spec)
	encodingCache[name] = enc
	return enc, nil
}

// GetEncodingForModel returns a ready-to-use Encoding for a model name
// (e.g. "gpt-4o", "gpt-3.5-turbo"). It resolves the model to an encoding
// name using the built-in registry.
func GetEncodingForModel(model string) (*Encoding, error) {
	name, err := ModelToEncodingName(model)
	if err != nil {
		return nil, err
	}
	return GetEncoding(name)
}

// Version returns the turbotoken native library version string.
func Version() string {
	return ffiVersion()
}
