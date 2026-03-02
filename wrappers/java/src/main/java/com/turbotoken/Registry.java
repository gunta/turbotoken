package com.turbotoken;

import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Encoding registry -- maps encoding names and model names to EncodingSpec instances.
 * Mirrors the Python _registry.py exactly.
 */
public final class Registry {

    private Registry() {}

    /* ── Special token constants ───────────────────────────────────────── */

    public static final String ENDOFTEXT = "<|endoftext|>";
    public static final String FIM_PREFIX = "<|fim_prefix|>";
    public static final String FIM_MIDDLE = "<|fim_middle|>";
    public static final String FIM_SUFFIX = "<|fim_suffix|>";
    public static final String ENDOFPROMPT = "<|endofprompt|>";

    /* ── Pattern strings ──────────────────────────────────────────────── */

    private static final String R50K_PAT_STR =
        "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++$|\\s+(?!\\S)|\\s";

    private static final String CL100K_PAT_STR =
        "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s";

    private static final String O200K_PAT_STR = String.join("|",
        "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
        "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
        "\\p{N}{1,3}",
        " ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*",
        "\\s*[\\r\\n]+",
        "\\s+(?!\\S)",
        "\\s+"
    );

    /* ── EncodingSpec ─────────────────────────────────────────────────── */

    public static final class EncodingSpec {
        private final String name;
        private final String rankFileUrl;
        private final String patStr;
        private final Map<String, Integer> specialTokens;
        private final int nVocab;

        public EncodingSpec(String name, String rankFileUrl, String patStr,
                            Map<String, Integer> specialTokens, int nVocab) {
            this.name = name;
            this.rankFileUrl = rankFileUrl;
            this.patStr = patStr;
            this.specialTokens = Collections.unmodifiableMap(new HashMap<>(specialTokens));
            this.nVocab = nVocab;
        }

        public String getName()                     { return name; }
        public String getRankFileUrl()               { return rankFileUrl; }
        public String getPatStr()                    { return patStr; }
        public Map<String, Integer> getSpecialTokens() { return specialTokens; }
        public int getNVocab()                       { return nVocab; }
        public int getEotToken()                     { return specialTokens.get(ENDOFTEXT); }
    }

    /* ── Encoding specs ──────────────────────────────────────────────── */

    private static final Map<String, EncodingSpec> ENCODING_SPECS;

    static {
        Map<String, EncodingSpec> m = new HashMap<>();

        m.put("o200k_base", new EncodingSpec(
            "o200k_base",
            "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
            O200K_PAT_STR,
            mapOf(ENDOFTEXT, 199999, ENDOFPROMPT, 200018),
            200019
        ));

        m.put("cl100k_base", new EncodingSpec(
            "cl100k_base",
            "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
            CL100K_PAT_STR,
            mapOf(ENDOFTEXT, 100257, FIM_PREFIX, 100258, FIM_MIDDLE, 100259,
                  FIM_SUFFIX, 100260, ENDOFPROMPT, 100276),
            100277
        ));

        m.put("p50k_base", new EncodingSpec(
            "p50k_base",
            "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
            R50K_PAT_STR,
            mapOf(ENDOFTEXT, 50256),
            50281
        ));

        m.put("r50k_base", new EncodingSpec(
            "r50k_base",
            "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
            R50K_PAT_STR,
            mapOf(ENDOFTEXT, 50256),
            50257
        ));

        m.put("gpt2", new EncodingSpec(
            "gpt2",
            "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
            R50K_PAT_STR,
            mapOf(ENDOFTEXT, 50256),
            50257
        ));

        m.put("p50k_edit", new EncodingSpec(
            "p50k_edit",
            "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
            R50K_PAT_STR,
            mapOf(ENDOFTEXT, 50256),
            50281
        ));

        m.put("o200k_harmony", new EncodingSpec(
            "o200k_harmony",
            "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
            O200K_PAT_STR,
            mapOf(ENDOFTEXT, 199999, ENDOFPROMPT, 200018),
            200019
        ));

        ENCODING_SPECS = Collections.unmodifiableMap(m);
    }

    /* ── Model-to-encoding mappings ──────────────────────────────────── */

    private static final Map<String, String> MODEL_TO_ENCODING;

    static {
        Map<String, String> m = new HashMap<>();
        m.put("o1", "o200k_base");
        m.put("o3", "o200k_base");
        m.put("o4-mini", "o200k_base");
        m.put("gpt-5", "o200k_base");
        m.put("gpt-4.1", "o200k_base");
        m.put("gpt-4o", "o200k_base");
        m.put("gpt-4o-mini", "o200k_base");
        m.put("gpt-4.1-mini", "o200k_base");
        m.put("gpt-4.1-nano", "o200k_base");
        m.put("gpt-oss-120b", "o200k_harmony");
        m.put("gpt-4", "cl100k_base");
        m.put("gpt-3.5-turbo", "cl100k_base");
        m.put("gpt-3.5", "cl100k_base");
        m.put("gpt-35-turbo", "cl100k_base");
        m.put("davinci-002", "cl100k_base");
        m.put("babbage-002", "cl100k_base");
        m.put("text-embedding-ada-002", "cl100k_base");
        m.put("text-embedding-3-small", "cl100k_base");
        m.put("text-embedding-3-large", "cl100k_base");
        m.put("text-davinci-003", "p50k_base");
        m.put("text-davinci-002", "p50k_base");
        m.put("text-davinci-001", "r50k_base");
        m.put("text-curie-001", "r50k_base");
        m.put("text-babbage-001", "r50k_base");
        m.put("text-ada-001", "r50k_base");
        m.put("davinci", "r50k_base");
        m.put("curie", "r50k_base");
        m.put("babbage", "r50k_base");
        m.put("ada", "r50k_base");
        m.put("code-davinci-002", "p50k_base");
        m.put("code-davinci-001", "p50k_base");
        m.put("code-cushman-002", "p50k_base");
        m.put("code-cushman-001", "p50k_base");
        m.put("davinci-codex", "p50k_base");
        m.put("cushman-codex", "p50k_base");
        m.put("text-davinci-edit-001", "p50k_edit");
        m.put("code-davinci-edit-001", "p50k_edit");
        m.put("text-similarity-davinci-001", "r50k_base");
        m.put("text-similarity-curie-001", "r50k_base");
        m.put("text-similarity-babbage-001", "r50k_base");
        m.put("text-similarity-ada-001", "r50k_base");
        m.put("text-search-davinci-doc-001", "r50k_base");
        m.put("text-search-curie-doc-001", "r50k_base");
        m.put("text-search-babbage-doc-001", "r50k_base");
        m.put("text-search-ada-doc-001", "r50k_base");
        m.put("code-search-babbage-code-001", "r50k_base");
        m.put("code-search-ada-code-001", "r50k_base");
        m.put("gpt2", "gpt2");
        m.put("gpt-2", "r50k_base");
        MODEL_TO_ENCODING = Collections.unmodifiableMap(m);
    }

    private static final LinkedHashMap<String, String> MODEL_PREFIX_TO_ENCODING;

    static {
        // LinkedHashMap preserves insertion order for prefix matching
        LinkedHashMap<String, String> m = new LinkedHashMap<>();
        m.put("o1-", "o200k_base");
        m.put("o3-", "o200k_base");
        m.put("o4-mini-", "o200k_base");
        m.put("gpt-5-", "o200k_base");
        m.put("gpt-4.5-", "o200k_base");
        m.put("gpt-4.1-", "o200k_base");
        m.put("chatgpt-4o-", "o200k_base");
        m.put("gpt-4o-", "o200k_base");
        m.put("gpt-oss-", "o200k_harmony");
        m.put("gpt-4-", "cl100k_base");
        m.put("gpt-3.5-turbo-", "cl100k_base");
        m.put("gpt-35-turbo-", "cl100k_base");
        m.put("ft:gpt-4o", "o200k_base");
        m.put("ft:gpt-4", "cl100k_base");
        m.put("ft:gpt-3.5-turbo", "cl100k_base");
        m.put("ft:davinci-002", "cl100k_base");
        m.put("ft:babbage-002", "cl100k_base");
        MODEL_PREFIX_TO_ENCODING = m;
    }

    /* ── Public API ──────────────────────────────────────────────────── */

    /**
     * Returns the EncodingSpec for the given encoding name.
     * @throws IllegalArgumentException if the encoding name is unknown
     */
    public static EncodingSpec getEncodingSpec(String name) {
        EncodingSpec spec = ENCODING_SPECS.get(name);
        if (spec == null) {
            throw new IllegalArgumentException(
                "Unknown encoding '" + name + "'. Supported encodings: "
                + String.join(", ", listEncodingNames())
            );
        }
        return spec;
    }

    /**
     * Maps a model name to its encoding name.
     * Tries exact match first, then prefix match.
     * @throws IllegalArgumentException if the model cannot be mapped
     */
    public static String modelToEncoding(String model) {
        String enc = MODEL_TO_ENCODING.get(model);
        if (enc != null) {
            return enc;
        }
        for (Map.Entry<String, String> entry : MODEL_PREFIX_TO_ENCODING.entrySet()) {
            if (model.startsWith(entry.getKey())) {
                return entry.getValue();
            }
        }
        throw new IllegalArgumentException(
            "Could not automatically map '" + model + "' to an encoding. "
            + "Use getEncoding(name) to select one explicitly."
        );
    }

    /**
     * Returns a sorted list of all supported encoding names.
     */
    public static List<String> listEncodingNames() {
        return ENCODING_SPECS.keySet().stream().sorted().collect(Collectors.toList());
    }

    /* ── Helpers ──────────────────────────────────────────────────────── */

    private static Map<String, Integer> mapOf(String k1, int v1) {
        Map<String, Integer> m = new HashMap<>();
        m.put(k1, v1);
        return m;
    }

    private static Map<String, Integer> mapOf(String k1, int v1, String k2, int v2) {
        Map<String, Integer> m = new HashMap<>();
        m.put(k1, v1);
        m.put(k2, v2);
        return m;
    }

    private static Map<String, Integer> mapOf(String k1, int v1, String k2, int v2,
                                               String k3, int v3, String k4, int v4,
                                               String k5, int v5) {
        Map<String, Integer> m = new HashMap<>();
        m.put(k1, v1);
        m.put(k2, v2);
        m.put(k3, v3);
        m.put(k4, v4);
        m.put(k5, v5);
        return m;
    }
}
