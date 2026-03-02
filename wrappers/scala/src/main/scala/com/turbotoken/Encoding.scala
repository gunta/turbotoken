package com.turbotoken

import scala.jdk.CollectionConverters._

/** A loaded BPE encoding. Thread-safe after construction.
  *
  * Wraps the Java com.turbotoken.Encoding, providing Scala-idiomatic collection types.
  *
  * Use [[TurboToken.getEncoding]] or [[TurboToken.getEncodingForModel]] to obtain instances.
  */
class Encoding private[turbotoken] (private val javaEncoding: com.turbotoken.Encoding) {

  /** Returns the encoding name. */
  def name: String = javaEncoding.getName()

  /* ── Core operations ──────────────────────────────────────────── */

  /** Encodes text into BPE token IDs. */
  def encode(text: String): Seq[Int] =
    javaEncoding.encode(text).toSeq

  /** Decodes BPE token IDs back to a string. */
  def decode(tokens: Seq[Int]): String =
    javaEncoding.decode(tokens.toArray)

  /** Counts the number of tokens in the given text without allocating the token array. */
  def count(text: String): Int =
    javaEncoding.count(text)

  /** Alias for [[count]]. */
  def countTokens(text: String): Int = count(text)

  /** Checks if the text is within the given token limit.
    * Returns Some(tokenCount) if within the limit, or None if exceeded.
    */
  def isWithinTokenLimit(text: String, limit: Int): Option[Int] = {
    val result = javaEncoding.isWithinTokenLimit(text, limit)
    if (result.isPresent) Some(result.getAsInt) else None
  }

  /* ── Chat operations ──────────────────────────────────────────── */

  /** Encodes a list of chat messages into token IDs. */
  def encodeChat(messages: Seq[ChatMessage], options: ChatOptions = ChatOptions()): Seq[Int] = {
    val formatted = Chat.formatMessages(messages, options)
    encode(formatted)
  }

  /** Counts tokens in a list of chat messages. */
  def countChat(messages: Seq[ChatMessage], options: ChatOptions = ChatOptions()): Int = {
    val formatted = Chat.formatMessages(messages, options)
    count(formatted)
  }

  /** Checks if a chat conversation is within the token limit. */
  def isChatWithinTokenLimit(messages: Seq[ChatMessage], limit: Int, options: ChatOptions = ChatOptions()): Option[Int] = {
    val formatted = Chat.formatMessages(messages, options)
    isWithinTokenLimit(formatted, limit)
  }

  /* ── File operations ──────────────────────────────────────────── */

  /** Encodes the contents of a file into BPE token IDs. */
  def encodeFilePath(path: String): Seq[Int] =
    javaEncoding.encodeFilePath(path).toSeq

  /** Counts tokens in a file without reading it into Scala/Java memory. */
  def countFilePath(path: String): Int =
    javaEncoding.countFilePath(path)

  /** Checks if a file's contents are within the token limit. */
  def isFilePathWithinTokenLimit(path: String, limit: Int): Option[Int] = {
    val result = javaEncoding.isFilePathWithinTokenLimit(path, limit)
    if (result.isPresent) Some(result.getAsInt) else None
  }
}
