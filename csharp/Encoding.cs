using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace TurboToken
{
    /// <summary>
    /// A BPE encoding instance backed by a rank file.
    /// </summary>
    public sealed class Encoding : IDisposable
    {
        /// <summary>The encoding name.</summary>
        public string Name { get; }

        /// <summary>The encoding spec.</summary>
        public EncodingSpec Spec { get; }

        private byte[] _rankPayload;
        private GCHandle _rankHandle;
        private bool _disposed;

        internal Encoding(string name, EncodingSpec spec, byte[] rankPayload)
        {
            Name = name;
            Spec = spec;
            _rankPayload = rankPayload;
            _rankHandle = GCHandle.Alloc(_rankPayload, GCHandleType.Pinned);
        }

        private IntPtr RankPtr => _rankHandle.AddrOfPinnedObject();
        private UIntPtr RankLen => (UIntPtr)_rankPayload.Length;

        // MARK: - Encode

        /// <summary>Encode text to BPE token IDs.</summary>
        public uint[] Encode(string text)
        {
            ThrowIfDisposed();
            var textBytes = Encoding8.GetBytes(text);
            return CallTwoPassUInt32(textBytes, (txtPtr, txtLen, outPtr, outCap) =>
                NativeMethods.turbotoken_encode_bpe_from_ranks(
                    RankPtr, RankLen, txtPtr, txtLen, outPtr, outCap));
        }

        /// <summary>Decode BPE token IDs back to a UTF-8 string.</summary>
        public string Decode(uint[] tokens)
        {
            ThrowIfDisposed();
            var bytes = CallTwoPassUInt8(tokens, (tokPtr, tokLen, outPtr, outCap) =>
                NativeMethods.turbotoken_decode_bpe_from_ranks(
                    RankPtr, RankLen, tokPtr, tokLen, outPtr, outCap));
            return Encoding8.GetString(bytes);
        }

        // MARK: - Count

        /// <summary>Count the number of BPE tokens for the given text.</summary>
        public int Count(string text)
        {
            ThrowIfDisposed();
            var textBytes = Encoding8.GetBytes(text);
            unsafe
            {
                fixed (byte* txtPtr = textBytes)
                {
                    var result = NativeMethods.turbotoken_count_bpe_from_ranks(
                        RankPtr, RankLen,
                        (IntPtr)txtPtr, (UIntPtr)textBytes.Length);
                    var count = result.ToInt64();
                    if (count < 0)
                        throw new TurboTokenException($"count returned error code {count}");
                    return (int)count;
                }
            }
        }

        /// <summary>Alias for Count.</summary>
        public int CountTokens(string text) => Count(text);

        // MARK: - Token Limit

        /// <summary>
        /// Check if text is within a token limit.
        /// Returns the token count if within limit.
        /// Throws TokenLimitExceededException if exceeded.
        /// </summary>
        public int IsWithinTokenLimit(string text, int limit)
        {
            ThrowIfDisposed();
            var textBytes = Encoding8.GetBytes(text);
            unsafe
            {
                fixed (byte* txtPtr = textBytes)
                {
                    var result = NativeMethods.turbotoken_is_within_token_limit_bpe_from_ranks(
                        RankPtr, RankLen,
                        (IntPtr)txtPtr, (UIntPtr)textBytes.Length,
                        (UIntPtr)limit);
                    var code = result.ToInt64();
                    if (code == -2)
                        throw new TokenLimitExceededException(limit);
                    if (code < 0)
                        throw new TurboTokenException($"isWithinTokenLimit returned error code {code}");
                    return (int)code;
                }
            }
        }

        // MARK: - Chat

        /// <summary>Encode a chat conversation to token IDs.</summary>
        public uint[] EncodeChat(IReadOnlyList<ChatMessage> messages, ChatOptions? options = null)
        {
            var text = ChatFormatter.FormatChat(messages, options ?? new ChatOptions());
            return Encode(text);
        }

        /// <summary>Count tokens in a chat conversation.</summary>
        public int CountChat(IReadOnlyList<ChatMessage> messages, ChatOptions? options = null)
        {
            var text = ChatFormatter.FormatChat(messages, options ?? new ChatOptions());
            return Count(text);
        }

        /// <summary>Check if a chat conversation is within a token limit.</summary>
        public int IsChatWithinTokenLimit(IReadOnlyList<ChatMessage> messages, int limit, ChatOptions? options = null)
        {
            var text = ChatFormatter.FormatChat(messages, options ?? new ChatOptions());
            return IsWithinTokenLimit(text, limit);
        }

        // MARK: - File Operations

        /// <summary>Encode a file's contents to BPE token IDs.</summary>
        public uint[] EncodeFilePath(string path)
        {
            ThrowIfDisposed();
            var pathBytes = Encoding8.GetBytes(path);
            return CallTwoPassUInt32(pathBytes, (pPtr, pLen, outPtr, outCap) =>
                NativeMethods.turbotoken_encode_bpe_file_from_ranks(
                    RankPtr, RankLen, pPtr, pLen, outPtr, outCap));
        }

        /// <summary>Count tokens in a file.</summary>
        public int CountFilePath(string path)
        {
            ThrowIfDisposed();
            var pathBytes = Encoding8.GetBytes(path);
            unsafe
            {
                fixed (byte* pPtr = pathBytes)
                {
                    var result = NativeMethods.turbotoken_count_bpe_file_from_ranks(
                        RankPtr, RankLen,
                        (IntPtr)pPtr, (UIntPtr)pathBytes.Length);
                    var count = result.ToInt64();
                    if (count < 0)
                        throw new TurboTokenException($"countFilePath returned error code {count}");
                    return (int)count;
                }
            }
        }

        /// <summary>Check if a file's content is within a token limit.</summary>
        public int IsFilePathWithinTokenLimit(string path, int limit)
        {
            ThrowIfDisposed();
            var pathBytes = Encoding8.GetBytes(path);
            unsafe
            {
                fixed (byte* pPtr = pathBytes)
                {
                    var result = NativeMethods.turbotoken_is_within_token_limit_bpe_file_from_ranks(
                        RankPtr, RankLen,
                        (IntPtr)pPtr, (UIntPtr)pathBytes.Length,
                        (UIntPtr)limit);
                    var code = result.ToInt64();
                    if (code == -2)
                        throw new TokenLimitExceededException(limit);
                    if (code < 0)
                        throw new TurboTokenException($"isFilePathWithinTokenLimit returned error code {code}");
                    return (int)code;
                }
            }
        }

        // MARK: - Two-pass helpers

        private delegate IntPtr TwoPassUInt32Fn(IntPtr input, UIntPtr inputLen, IntPtr outBuf, UIntPtr outCap);
        private delegate IntPtr TwoPassUInt8Fn(IntPtr input, UIntPtr inputLen, IntPtr outBuf, UIntPtr outCap);

        private unsafe uint[] CallTwoPassUInt32(byte[] input, TwoPassUInt32Fn fn)
        {
            fixed (byte* inPtr = input)
            {
                var sizeResult = fn((IntPtr)inPtr, (UIntPtr)input.Length, IntPtr.Zero, UIntPtr.Zero);
                var count = sizeResult.ToInt64();
                if (count < 0)
                    throw new TurboTokenException($"FFI size query returned error code {count}");
                if (count == 0)
                    return Array.Empty<uint>();

                var buffer = new uint[count];
                fixed (uint* outPtr = buffer)
                {
                    var written = fn((IntPtr)inPtr, (UIntPtr)input.Length, (IntPtr)outPtr, (UIntPtr)count);
                    var writtenCount = written.ToInt64();
                    if (writtenCount < 0)
                        throw new TurboTokenException($"FFI fill returned error code {writtenCount}");
                    if (writtenCount < count)
                        Array.Resize(ref buffer, (int)writtenCount);
                }
                return buffer;
            }
        }

        private unsafe byte[] CallTwoPassUInt8(uint[] input, TwoPassUInt8Fn fn)
        {
            fixed (uint* inPtr = input)
            {
                var sizeResult = fn((IntPtr)inPtr, (UIntPtr)input.Length, IntPtr.Zero, UIntPtr.Zero);
                var count = sizeResult.ToInt64();
                if (count < 0)
                    throw new TurboTokenException($"FFI size query returned error code {count}");
                if (count == 0)
                    return Array.Empty<byte>();

                var buffer = new byte[count];
                fixed (byte* outPtr = buffer)
                {
                    var written = fn((IntPtr)inPtr, (UIntPtr)input.Length, (IntPtr)outPtr, (UIntPtr)count);
                    var writtenCount = written.ToInt64();
                    if (writtenCount < 0)
                        throw new TurboTokenException($"FFI fill returned error code {writtenCount}");
                    if (writtenCount < count)
                        Array.Resize(ref buffer, (int)writtenCount);
                }
                return buffer;
            }
        }

        private static readonly System.Text.Encoding Encoding8 = System.Text.Encoding.UTF8;

        // MARK: - IDisposable

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(Encoding));
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                _disposed = true;
                if (_rankHandle.IsAllocated)
                    _rankHandle.Free();
            }
        }
    }
}
