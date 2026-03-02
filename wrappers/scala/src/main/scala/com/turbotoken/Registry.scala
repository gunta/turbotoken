package com.turbotoken

import scala.collection.immutable.ListMap

/** Specification for a BPE encoding. */
case class EncodingSpec(
  name: String,
  rankFileUrl: String,
  patStr: String,
  specialTokens: Map[String, Int],
  nVocab: Int
)

/** Encoding registry -- maps encoding names and model names to EncodingSpec instances.
  * Mirrors the Python _registry.py exactly.
  */
object Registry {

  /* ── Special token constants ─────────────────────────────────────── */

  val ENDOFTEXT   = "<|endoftext|>"
  val FIM_PREFIX  = "<|fim_prefix|>"
  val FIM_MIDDLE  = "<|fim_middle|>"
  val FIM_SUFFIX  = "<|fim_suffix|>"
  val ENDOFPROMPT = "<|endofprompt|>"

  /* ── Pattern strings ────────────────────────────────────────────── */

  private val R50K_PAT_STR =
    "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++$|\\s+(?!\\S)|\\s"

  private val CL100K_PAT_STR =
    "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s"

  private val O200K_PAT_STR = Seq(
    "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
    "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
    "\\p{N}{1,3}",
    " ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*",
    "\\s*[\\r\\n]+",
    "\\s+(?!\\S)",
    "\\s+"
  ).mkString("|")

  /* ── Encoding specs ────────────────────────────────────────────── */

  private val encodingSpecs: Map[String, EncodingSpec] = Map(
    "o200k_base" -> EncodingSpec(
      name = "o200k_base",
      rankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
      patStr = O200K_PAT_STR,
      specialTokens = Map(ENDOFTEXT -> 199999, ENDOFPROMPT -> 200018),
      nVocab = 200019
    ),
    "cl100k_base" -> EncodingSpec(
      name = "cl100k_base",
      rankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
      patStr = CL100K_PAT_STR,
      specialTokens = Map(
        ENDOFTEXT  -> 100257,
        FIM_PREFIX -> 100258,
        FIM_MIDDLE -> 100259,
        FIM_SUFFIX -> 100260,
        ENDOFPROMPT -> 100276
      ),
      nVocab = 100277
    ),
    "p50k_base" -> EncodingSpec(
      name = "p50k_base",
      rankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
      patStr = R50K_PAT_STR,
      specialTokens = Map(ENDOFTEXT -> 50256),
      nVocab = 50281
    ),
    "r50k_base" -> EncodingSpec(
      name = "r50k_base",
      rankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
      patStr = R50K_PAT_STR,
      specialTokens = Map(ENDOFTEXT -> 50256),
      nVocab = 50257
    ),
    "gpt2" -> EncodingSpec(
      name = "gpt2",
      rankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
      patStr = R50K_PAT_STR,
      specialTokens = Map(ENDOFTEXT -> 50256),
      nVocab = 50257
    ),
    "p50k_edit" -> EncodingSpec(
      name = "p50k_edit",
      rankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
      patStr = R50K_PAT_STR,
      specialTokens = Map(ENDOFTEXT -> 50256),
      nVocab = 50281
    ),
    "o200k_harmony" -> EncodingSpec(
      name = "o200k_harmony",
      rankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
      patStr = O200K_PAT_STR,
      specialTokens = Map(ENDOFTEXT -> 199999, ENDOFPROMPT -> 200018),
      nVocab = 200019
    )
  )

  /* ── Model-to-encoding mappings ──────────────────────────────── */

  private val modelToEncodingMap: Map[String, String] = Map(
    "o1"                              -> "o200k_base",
    "o3"                              -> "o200k_base",
    "o4-mini"                         -> "o200k_base",
    "gpt-5"                           -> "o200k_base",
    "gpt-4.1"                         -> "o200k_base",
    "gpt-4o"                          -> "o200k_base",
    "gpt-4o-mini"                     -> "o200k_base",
    "gpt-4.1-mini"                    -> "o200k_base",
    "gpt-4.1-nano"                    -> "o200k_base",
    "gpt-oss-120b"                    -> "o200k_harmony",
    "gpt-4"                           -> "cl100k_base",
    "gpt-3.5-turbo"                   -> "cl100k_base",
    "gpt-3.5"                         -> "cl100k_base",
    "gpt-35-turbo"                    -> "cl100k_base",
    "davinci-002"                     -> "cl100k_base",
    "babbage-002"                     -> "cl100k_base",
    "text-embedding-ada-002"          -> "cl100k_base",
    "text-embedding-3-small"          -> "cl100k_base",
    "text-embedding-3-large"          -> "cl100k_base",
    "text-davinci-003"                -> "p50k_base",
    "text-davinci-002"                -> "p50k_base",
    "text-davinci-001"                -> "r50k_base",
    "text-curie-001"                  -> "r50k_base",
    "text-babbage-001"                -> "r50k_base",
    "text-ada-001"                    -> "r50k_base",
    "davinci"                         -> "r50k_base",
    "curie"                           -> "r50k_base",
    "babbage"                         -> "r50k_base",
    "ada"                             -> "r50k_base",
    "code-davinci-002"                -> "p50k_base",
    "code-davinci-001"                -> "p50k_base",
    "code-cushman-002"                -> "p50k_base",
    "code-cushman-001"                -> "p50k_base",
    "davinci-codex"                   -> "p50k_base",
    "cushman-codex"                   -> "p50k_base",
    "text-davinci-edit-001"           -> "p50k_edit",
    "code-davinci-edit-001"           -> "p50k_edit",
    "text-similarity-davinci-001"     -> "r50k_base",
    "text-similarity-curie-001"       -> "r50k_base",
    "text-similarity-babbage-001"     -> "r50k_base",
    "text-similarity-ada-001"         -> "r50k_base",
    "text-search-davinci-doc-001"     -> "r50k_base",
    "text-search-curie-doc-001"       -> "r50k_base",
    "text-search-babbage-doc-001"     -> "r50k_base",
    "text-search-ada-doc-001"         -> "r50k_base",
    "code-search-babbage-code-001"    -> "r50k_base",
    "code-search-ada-code-001"        -> "r50k_base",
    "gpt2"                            -> "gpt2",
    "gpt-2"                           -> "r50k_base"
  )

  /** Prefix-to-encoding mapping. Order matters -- checked sequentially. */
  private val modelPrefixToEncoding: Seq[(String, String)] = Seq(
    "o1-"               -> "o200k_base",
    "o3-"               -> "o200k_base",
    "o4-mini-"          -> "o200k_base",
    "gpt-5-"            -> "o200k_base",
    "gpt-4.5-"          -> "o200k_base",
    "gpt-4.1-"          -> "o200k_base",
    "chatgpt-4o-"       -> "o200k_base",
    "gpt-4o-"           -> "o200k_base",
    "gpt-oss-"          -> "o200k_harmony",
    "gpt-4-"            -> "cl100k_base",
    "gpt-3.5-turbo-"    -> "cl100k_base",
    "gpt-35-turbo-"     -> "cl100k_base",
    "ft:gpt-4o"         -> "o200k_base",
    "ft:gpt-4"          -> "cl100k_base",
    "ft:gpt-3.5-turbo"  -> "cl100k_base",
    "ft:davinci-002"    -> "cl100k_base",
    "ft:babbage-002"    -> "cl100k_base"
  )

  /* ── Public API ────────────────────────────────────────────────── */

  /** Returns the EncodingSpec for the given encoding name. */
  def getEncodingSpec(name: String): EncodingSpec =
    encodingSpecs.getOrElse(name, throw new UnknownEncodingException(name))

  /** Maps a model name to its encoding name. Tries exact match, then prefix match. */
  def modelToEncoding(model: String): String = {
    modelToEncodingMap.get(model) match {
      case Some(enc) => enc
      case None =>
        modelPrefixToEncoding.find { case (prefix, _) => model.startsWith(prefix) } match {
          case Some((_, enc)) => enc
          case None           => throw new UnknownModelException(model)
        }
    }
  }

  /** Returns a sorted list of all supported encoding names. */
  def listEncodingNames: Seq[String] = encodingSpecs.keys.toSeq.sorted
}
