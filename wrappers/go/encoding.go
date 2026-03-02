package turbotoken

import (
	"sync"
)

// Encoding holds a loaded BPE encoding with its rank data, ready for
// encoding, decoding, and counting operations.
type Encoding struct {
	name        string
	spec        *EncodingSpec
	rankPayload []byte
	once        sync.Once
	loadErr     error
}

// newEncoding creates an Encoding from a spec, deferring rank file loading.
func newEncoding(spec *EncodingSpec) *Encoding {
	return &Encoding{
		name: spec.Name,
		spec: spec,
	}
}

// ensureLoaded loads the rank file if not already loaded.
func (enc *Encoding) ensureLoaded() error {
	enc.once.Do(func() {
		enc.rankPayload, enc.loadErr = ReadRankFile(enc.name)
	})
	return enc.loadErr
}

// Name returns the encoding name.
func (enc *Encoding) Name() string {
	return enc.name
}

// NVocab returns the vocabulary size.
func (enc *Encoding) NVocab() int {
	return enc.spec.NVocab
}

// Encode tokenizes text into BPE token IDs.
func (enc *Encoding) Encode(text string) ([]uint32, error) {
	if err := enc.ensureLoaded(); err != nil {
		return nil, err
	}
	return ffiEncodeBPE(enc.rankPayload, []byte(text))
}

// Decode converts BPE token IDs back to a UTF-8 string.
func (enc *Encoding) Decode(tokens []uint32) (string, error) {
	if err := enc.ensureLoaded(); err != nil {
		return "", err
	}
	data, err := ffiDecodeBPE(enc.rankPayload, tokens)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// Count returns the number of BPE tokens in text without materializing the token array.
func (enc *Encoding) Count(text string) (int, error) {
	if err := enc.ensureLoaded(); err != nil {
		return 0, err
	}
	return ffiCountBPE(enc.rankPayload, []byte(text))
}

// CountTokens is an alias for Count.
func (enc *Encoding) CountTokens(text string) (int, error) {
	return enc.Count(text)
}

// IsWithinTokenLimit checks if text tokenizes to at most limit tokens.
// Returns (tokenCount, true, nil) if within limit, (0, false, nil) if exceeded.
func (enc *Encoding) IsWithinTokenLimit(text string, limit int) (int, bool, error) {
	if err := enc.ensureLoaded(); err != nil {
		return 0, false, err
	}
	return ffiIsWithinTokenLimit(enc.rankPayload, []byte(text), limit)
}

// EncodeChat encodes a sequence of chat messages into BPE tokens using
// the configured chat template.
func (enc *Encoding) EncodeChat(messages []ChatMessage, opts *ChatOptions) ([]uint32, error) {
	formatted := formatChat(messages, opts)
	return enc.Encode(formatted)
}

// CountChat counts BPE tokens for a chat message sequence.
func (enc *Encoding) CountChat(messages []ChatMessage, opts *ChatOptions) (int, error) {
	formatted := formatChat(messages, opts)
	return enc.Count(formatted)
}

// IsChatWithinTokenLimit checks if chat messages tokenize within a limit.
func (enc *Encoding) IsChatWithinTokenLimit(messages []ChatMessage, limit int, opts *ChatOptions) (int, bool, error) {
	formatted := formatChat(messages, opts)
	return enc.IsWithinTokenLimit(formatted, limit)
}

// EncodeFilePath encodes the contents of a file into BPE tokens.
func (enc *Encoding) EncodeFilePath(path string) ([]uint32, error) {
	if err := enc.ensureLoaded(); err != nil {
		return nil, err
	}
	return ffiEncodeBPEFile(enc.rankPayload, path)
}

// CountFilePath counts BPE tokens in a file without materializing the token array.
func (enc *Encoding) CountFilePath(path string) (int, error) {
	if err := enc.ensureLoaded(); err != nil {
		return 0, err
	}
	return ffiCountBPEFile(enc.rankPayload, path)
}
