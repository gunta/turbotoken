using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace TurboToken
{
    /// <summary>
    /// Static facade for TurboToken operations.
    /// </summary>
    public static class TurboTokenFacade
    {
        /// <summary>Get the native library version string.</summary>
        public static string Version
        {
            get
            {
                var ptr = NativeMethods.turbotoken_version();
                return ptr == IntPtr.Zero ? "unknown" : Marshal.PtrToStringAnsi(ptr) ?? "unknown";
            }
        }

        /// <summary>Clear the internal rank table cache.</summary>
        public static void ClearCache()
        {
            NativeMethods.turbotoken_clear_rank_table_cache();
        }

        /// <summary>Get an encoding by name (e.g. "cl100k_base", "o200k_base").</summary>
        public static async Task<Encoding> GetEncodingAsync(string name, CancellationToken ct = default)
        {
            var spec = Registry.GetEncodingSpec(name);
            var rankData = await RankCache.ReadRankFileAsync(spec.Name, ct).ConfigureAwait(false);
            return new Encoding(spec.Name, spec, rankData);
        }

        /// <summary>Get the encoding for a model name (e.g. "gpt-4o", "gpt-3.5-turbo").</summary>
        public static async Task<Encoding> GetEncodingForModelAsync(string model, CancellationToken ct = default)
        {
            var encodingName = Registry.ModelToEncoding(model);
            return await GetEncodingAsync(encodingName, ct).ConfigureAwait(false);
        }

        /// <summary>List all known encoding names.</summary>
        public static IReadOnlyList<string> ListEncodingNames() => Registry.ListEncodingNames();
    }
}
