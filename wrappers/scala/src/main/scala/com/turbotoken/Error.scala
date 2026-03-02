package com.turbotoken

/** Base exception for turbotoken errors. */
class TurbotokenException(message: String) extends RuntimeException(message)

/** Thrown when an unknown encoding name is requested. */
class UnknownEncodingException(name: String)
  extends TurbotokenException(s"Unknown encoding '$name'. Use TurboToken.listEncodingNames to see supported encodings.")

/** Thrown when a model name cannot be mapped to an encoding. */
class UnknownModelException(model: String)
  extends TurbotokenException(
    s"Could not automatically map '$model' to an encoding. Use TurboToken.getEncoding(name) to select one explicitly."
  )
