(ns turbotoken.registry
  "Encoding registry -- maps encoding names and model names to encoding specs.
   Mirrors the Python _registry.py exactly.")

;; ── Special token constants ──────────────────────────────────────────

(def ^:const ENDOFTEXT   "<|endoftext|>")
(def ^:const FIM_PREFIX  "<|fim_prefix|>")
(def ^:const FIM_MIDDLE  "<|fim_middle|>")
(def ^:const FIM_SUFFIX  "<|fim_suffix|>")
(def ^:const ENDOFPROMPT "<|endofprompt|>")

;; ── Pattern strings ──────────────────────────────────────────────────

(def ^:private r50k-pat-str
  "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++$|\\s+(?!\\S)|\\s")

(def ^:private cl100k-pat-str
  "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s")

(def ^:private o200k-pat-str
  (clojure.string/join "|"
    ["[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?"
     "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?"
     "\\p{N}{1,3}"
     " ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*"
     "\\s*[\\r\\n]+"
     "\\s+(?!\\S)"
     "\\s+"]))

;; ── Encoding specs ───────────────────────────────────────────────────

(def encoding-specs
  {"o200k_base"
   {:name          "o200k_base"
    :rank-file-url "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken"
    :pat-str       o200k-pat-str
    :special-tokens {ENDOFTEXT 199999, ENDOFPROMPT 200018}
    :n-vocab       200019}

   "cl100k_base"
   {:name          "cl100k_base"
    :rank-file-url "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken"
    :pat-str       cl100k-pat-str
    :special-tokens {ENDOFTEXT  100257
                     FIM_PREFIX 100258
                     FIM_MIDDLE 100259
                     FIM_SUFFIX 100260
                     ENDOFPROMPT 100276}
    :n-vocab       100277}

   "p50k_base"
   {:name          "p50k_base"
    :rank-file-url "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken"
    :pat-str       r50k-pat-str
    :special-tokens {ENDOFTEXT 50256}
    :n-vocab       50281}

   "r50k_base"
   {:name          "r50k_base"
    :rank-file-url "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken"
    :pat-str       r50k-pat-str
    :special-tokens {ENDOFTEXT 50256}
    :n-vocab       50257}

   "gpt2"
   {:name          "gpt2"
    :rank-file-url "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken"
    :pat-str       r50k-pat-str
    :special-tokens {ENDOFTEXT 50256}
    :n-vocab       50257}

   "p50k_edit"
   {:name          "p50k_edit"
    :rank-file-url "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken"
    :pat-str       r50k-pat-str
    :special-tokens {ENDOFTEXT 50256}
    :n-vocab       50281}

   "o200k_harmony"
   {:name          "o200k_harmony"
    :rank-file-url "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken"
    :pat-str       o200k-pat-str
    :special-tokens {ENDOFTEXT 199999, ENDOFPROMPT 200018}
    :n-vocab       200019}})

;; ── Model-to-encoding mappings ───────────────────────────────────────

(def model-to-encoding
  {"o1"                              "o200k_base"
   "o3"                              "o200k_base"
   "o4-mini"                         "o200k_base"
   "gpt-5"                           "o200k_base"
   "gpt-4.1"                         "o200k_base"
   "gpt-4o"                          "o200k_base"
   "gpt-4o-mini"                     "o200k_base"
   "gpt-4.1-mini"                    "o200k_base"
   "gpt-4.1-nano"                    "o200k_base"
   "gpt-oss-120b"                    "o200k_harmony"
   "gpt-4"                           "cl100k_base"
   "gpt-3.5-turbo"                   "cl100k_base"
   "gpt-3.5"                         "cl100k_base"
   "gpt-35-turbo"                    "cl100k_base"
   "davinci-002"                     "cl100k_base"
   "babbage-002"                     "cl100k_base"
   "text-embedding-ada-002"          "cl100k_base"
   "text-embedding-3-small"          "cl100k_base"
   "text-embedding-3-large"          "cl100k_base"
   "text-davinci-003"                "p50k_base"
   "text-davinci-002"                "p50k_base"
   "text-davinci-001"                "r50k_base"
   "text-curie-001"                  "r50k_base"
   "text-babbage-001"                "r50k_base"
   "text-ada-001"                    "r50k_base"
   "davinci"                         "r50k_base"
   "curie"                           "r50k_base"
   "babbage"                         "r50k_base"
   "ada"                             "r50k_base"
   "code-davinci-002"                "p50k_base"
   "code-davinci-001"                "p50k_base"
   "code-cushman-002"                "p50k_base"
   "code-cushman-001"                "p50k_base"
   "davinci-codex"                   "p50k_base"
   "cushman-codex"                   "p50k_base"
   "text-davinci-edit-001"           "p50k_edit"
   "code-davinci-edit-001"           "p50k_edit"
   "text-similarity-davinci-001"     "r50k_base"
   "text-similarity-curie-001"       "r50k_base"
   "text-similarity-babbage-001"     "r50k_base"
   "text-similarity-ada-001"         "r50k_base"
   "text-search-davinci-doc-001"     "r50k_base"
   "text-search-curie-doc-001"       "r50k_base"
   "text-search-babbage-doc-001"     "r50k_base"
   "text-search-ada-doc-001"         "r50k_base"
   "code-search-babbage-code-001"    "r50k_base"
   "code-search-ada-code-001"        "r50k_base"
   "gpt2"                            "gpt2"
   "gpt-2"                           "r50k_base"})

(def model-prefix-to-encoding
  [["o1-"               "o200k_base"]
   ["o3-"               "o200k_base"]
   ["o4-mini-"          "o200k_base"]
   ["gpt-5-"            "o200k_base"]
   ["gpt-4.5-"          "o200k_base"]
   ["gpt-4.1-"          "o200k_base"]
   ["chatgpt-4o-"       "o200k_base"]
   ["gpt-4o-"           "o200k_base"]
   ["gpt-oss-"          "o200k_harmony"]
   ["gpt-4-"            "cl100k_base"]
   ["gpt-3.5-turbo-"    "cl100k_base"]
   ["gpt-35-turbo-"     "cl100k_base"]
   ["ft:gpt-4o"         "o200k_base"]
   ["ft:gpt-4"          "cl100k_base"]
   ["ft:gpt-3.5-turbo"  "cl100k_base"]
   ["ft:davinci-002"    "cl100k_base"]
   ["ft:babbage-002"    "cl100k_base"]])

;; ── Public API ───────────────────────────────────────────────────────

(defn list-encoding-names
  "Returns a sorted sequence of all supported encoding names."
  []
  (sort (keys encoding-specs)))

(defn get-encoding-spec
  "Returns the encoding spec map for the given encoding name.
   Throws ExceptionInfo if the encoding name is unknown."
  [name]
  (or (get encoding-specs name)
      (throw (ex-info (str "Unknown encoding '" name "'. Supported encodings: "
                           (clojure.string/join ", " (list-encoding-names)))
                      {:type :unknown-encoding :name name}))))

(defn model->encoding
  "Maps a model name to its encoding name.
   Tries exact match first, then prefix match.
   Throws ExceptionInfo if the model cannot be mapped."
  [model]
  (or (get model-to-encoding model)
      (some (fn [[prefix enc]]
              (when (.startsWith ^String model prefix)
                enc))
            model-prefix-to-encoding)
      (throw (ex-info (str "Could not automatically map '" model "' to an encoding. "
                           "Use get-encoding to select one explicitly.")
                      {:type :unknown-model :model model}))))
