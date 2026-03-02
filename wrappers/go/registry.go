package turbotoken

import (
	"fmt"
	"sort"
	"strings"
)

// EncodingSpec describes a BPE encoding: its rank file URL, regex pattern,
// special tokens, and vocabulary size.
type EncodingSpec struct {
	Name          string
	RankFileURL   string
	PatStr        string
	SpecialTokens map[string]int
	NVocab        int
}

// Special token constants.
const (
	EndOfText   = "<|endoftext|>"
	FIMPrefix   = "<|fim_prefix|>"
	FIMMiddle   = "<|fim_middle|>"
	FIMSuffix   = "<|fim_suffix|>"
	EndOfPrompt = "<|endofprompt|>"
)

// Regex pattern strings matching tiktoken definitions.
const (
	r50kPatStr = `'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s`

	cl100kPatStr = `'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s`
)

// o200kPatStr is built by joining sub-patterns.
var o200kPatStr = strings.Join([]string{
	`[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?`,
	`[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?`,
	`\p{N}{1,3}`,
	` ?[^\s\p{L}\p{N}]+[\r\n/]*`,
	`\s*[\r\n]+`,
	`\s+(?!\S)`,
	`\s+`,
}, "|")

var encodingSpecs = map[string]*EncodingSpec{
	"o200k_base": {
		Name:        "o200k_base",
		RankFileURL: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
		PatStr:      o200kPatStr,
		SpecialTokens: map[string]int{
			EndOfText:   199999,
			EndOfPrompt: 200018,
		},
		NVocab: 200019,
	},
	"cl100k_base": {
		Name:        "cl100k_base",
		RankFileURL: "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
		PatStr:      cl100kPatStr,
		SpecialTokens: map[string]int{
			EndOfText:   100257,
			FIMPrefix:   100258,
			FIMMiddle:   100259,
			FIMSuffix:   100260,
			EndOfPrompt: 100276,
		},
		NVocab: 100277,
	},
	"p50k_base": {
		Name:        "p50k_base",
		RankFileURL: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
		PatStr:      r50kPatStr,
		SpecialTokens: map[string]int{
			EndOfText: 50256,
		},
		NVocab: 50281,
	},
	"r50k_base": {
		Name:        "r50k_base",
		RankFileURL: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
		PatStr:      r50kPatStr,
		SpecialTokens: map[string]int{
			EndOfText: 50256,
		},
		NVocab: 50257,
	},
	"gpt2": {
		Name:        "gpt2",
		RankFileURL: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
		PatStr:      r50kPatStr,
		SpecialTokens: map[string]int{
			EndOfText: 50256,
		},
		NVocab: 50257,
	},
	"p50k_edit": {
		Name:        "p50k_edit",
		RankFileURL: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
		PatStr:      r50kPatStr,
		SpecialTokens: map[string]int{
			EndOfText: 50256,
		},
		NVocab: 50281,
	},
	"o200k_harmony": {
		Name:        "o200k_harmony",
		RankFileURL: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
		PatStr:      o200kPatStr,
		SpecialTokens: map[string]int{
			EndOfText:   199999,
			EndOfPrompt: 200018,
		},
		NVocab: 200019,
	},
}

// modelToEncoding maps exact model names to encoding names.
var modelToEncoding = map[string]string{
	"o1":                            "o200k_base",
	"o3":                            "o200k_base",
	"o4-mini":                       "o200k_base",
	"gpt-5":                         "o200k_base",
	"gpt-4.1":                       "o200k_base",
	"gpt-4o":                        "o200k_base",
	"gpt-4o-mini":                   "o200k_base",
	"gpt-4.1-mini":                  "o200k_base",
	"gpt-4.1-nano":                  "o200k_base",
	"gpt-oss-120b":                  "o200k_harmony",
	"gpt-4":                         "cl100k_base",
	"gpt-3.5-turbo":                 "cl100k_base",
	"gpt-3.5":                       "cl100k_base",
	"gpt-35-turbo":                  "cl100k_base",
	"davinci-002":                   "cl100k_base",
	"babbage-002":                   "cl100k_base",
	"text-embedding-ada-002":        "cl100k_base",
	"text-embedding-3-small":        "cl100k_base",
	"text-embedding-3-large":        "cl100k_base",
	"text-davinci-003":              "p50k_base",
	"text-davinci-002":              "p50k_base",
	"text-davinci-001":              "r50k_base",
	"text-curie-001":                "r50k_base",
	"text-babbage-001":              "r50k_base",
	"text-ada-001":                  "r50k_base",
	"davinci":                       "r50k_base",
	"curie":                         "r50k_base",
	"babbage":                       "r50k_base",
	"ada":                           "r50k_base",
	"code-davinci-002":              "p50k_base",
	"code-davinci-001":              "p50k_base",
	"code-cushman-002":              "p50k_base",
	"code-cushman-001":              "p50k_base",
	"davinci-codex":                 "p50k_base",
	"cushman-codex":                 "p50k_base",
	"text-davinci-edit-001":         "p50k_edit",
	"code-davinci-edit-001":         "p50k_edit",
	"text-similarity-davinci-001":   "r50k_base",
	"text-similarity-curie-001":     "r50k_base",
	"text-similarity-babbage-001":   "r50k_base",
	"text-similarity-ada-001":       "r50k_base",
	"text-search-davinci-doc-001":   "r50k_base",
	"text-search-curie-doc-001":     "r50k_base",
	"text-search-babbage-doc-001":   "r50k_base",
	"text-search-ada-doc-001":       "r50k_base",
	"code-search-babbage-code-001":  "r50k_base",
	"code-search-ada-code-001":      "r50k_base",
	"gpt2":                          "gpt2",
	"gpt-2":                         "r50k_base",
}

// modelPrefixToEncoding maps model name prefixes to encoding names.
// Order matters: longer prefixes should be checked first for correct matching.
var modelPrefixToEncoding = []struct {
	Prefix   string
	Encoding string
}{
	{"o1-", "o200k_base"},
	{"o3-", "o200k_base"},
	{"o4-mini-", "o200k_base"},
	{"gpt-5-", "o200k_base"},
	{"gpt-4.5-", "o200k_base"},
	{"gpt-4.1-", "o200k_base"},
	{"chatgpt-4o-", "o200k_base"},
	{"gpt-4o-", "o200k_base"},
	{"gpt-oss-", "o200k_harmony"},
	{"gpt-4-", "cl100k_base"},
	{"gpt-3.5-turbo-", "cl100k_base"},
	{"gpt-35-turbo-", "cl100k_base"},
	{"ft:gpt-4o", "o200k_base"},
	{"ft:gpt-4", "cl100k_base"},
	{"ft:gpt-3.5-turbo", "cl100k_base"},
	{"ft:davinci-002", "cl100k_base"},
	{"ft:babbage-002", "cl100k_base"},
}

// GetEncodingSpec returns the EncodingSpec for the given encoding name.
func GetEncodingSpec(name string) (*EncodingSpec, error) {
	spec, ok := encodingSpecs[name]
	if !ok {
		return nil, encodingError(name)
	}
	return spec, nil
}

// ModelToEncodingName returns the encoding name for a model identifier.
// It first checks exact matches, then prefix matches.
func ModelToEncodingName(model string) (string, error) {
	if enc, ok := modelToEncoding[model]; ok {
		return enc, nil
	}
	for _, entry := range modelPrefixToEncoding {
		if strings.HasPrefix(model, entry.Prefix) {
			return entry.Encoding, nil
		}
	}
	return "", fmt.Errorf("turbotoken: could not map model %q to an encoding; use GetEncoding(name) directly", model)
}

// ListEncodingNames returns a sorted list of all supported encoding names.
func ListEncodingNames() []string {
	names := make([]string, 0, len(encodingSpecs))
	for name := range encodingSpecs {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
