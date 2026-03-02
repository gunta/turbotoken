package com.turbotoken

import java.util.concurrent.ConcurrentHashMap

/** Main entry point for the turbotoken Scala API.
  *
  * {{{
  * val enc = TurboToken.getEncoding("cl100k_base")
  * val tokens = enc.encode("hello world")
  * val decoded = enc.decode(tokens)
  *
  * // Or by model name:
  * val enc2 = TurboToken.getEncodingForModel("gpt-4o")
  * }}}
  */
object TurboToken {

  private val cache = new ConcurrentHashMap[String, Encoding]()

  /** Returns the native library version string. */
  def version: String = com.turbotoken.TurboToken.version()

  /** Returns an Encoding for the given encoding name (e.g. "cl100k_base", "o200k_base").
    * Encoding instances are cached and reused.
    *
    * @throws UnknownEncodingException if the encoding name is unknown
    */
  def getEncoding(name: String): Encoding = {
    cache.computeIfAbsent(name, { k =>
      // Validate the name exists in our registry
      Registry.getEncodingSpec(k)
      // Delegate to Java for actual native loading
      val javaEnc = com.turbotoken.TurboToken.getEncoding(k)
      new Encoding(javaEnc)
    })
  }

  /** Returns an Encoding for the given model name (e.g. "gpt-4o", "gpt-3.5-turbo").
    *
    * @throws UnknownModelException if the model cannot be mapped to an encoding
    */
  def getEncodingForModel(model: String): Encoding = {
    val encodingName = Registry.modelToEncoding(model)
    getEncoding(encodingName)
  }

  /** Returns a sorted list of all supported encoding names. */
  def listEncodingNames: Seq[String] = Registry.listEncodingNames
}
