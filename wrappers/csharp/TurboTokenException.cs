using System;

namespace TurboToken
{
    /// <summary>
    /// Exception thrown by TurboToken operations.
    /// </summary>
    public class TurboTokenException : Exception
    {
        public TurboTokenException(string message) : base(message) { }
        public TurboTokenException(string message, Exception innerException) : base(message, innerException) { }
    }

    /// <summary>
    /// Thrown when an unknown encoding name is requested.
    /// </summary>
    public class UnknownEncodingException : TurboTokenException
    {
        public UnknownEncodingException(string message) : base(message) { }
    }

    /// <summary>
    /// Thrown when a model cannot be mapped to an encoding.
    /// </summary>
    public class UnknownModelException : TurboTokenException
    {
        public UnknownModelException(string message) : base(message) { }
    }

    /// <summary>
    /// Thrown when text exceeds a token limit.
    /// </summary>
    public class TokenLimitExceededException : TurboTokenException
    {
        public int Limit { get; }

        public TokenLimitExceededException(int limit)
            : base($"Token limit of {limit} exceeded")
        {
            Limit = limit;
        }
    }
}
