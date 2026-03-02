using System;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace TurboToken
{
    /// <summary>
    /// Cache for downloaded rank files.
    /// </summary>
    public static class RankCache
    {
        private static readonly HttpClient HttpClient = new HttpClient();

        /// <summary>
        /// Returns the cache directory for rank files.
        /// </summary>
        public static string CacheDir
        {
            get
            {
                var xdgCache = Environment.GetEnvironmentVariable("XDG_CACHE_HOME");
                var baseDir = !string.IsNullOrEmpty(xdgCache)
                    ? xdgCache
                    : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cache");
                return Path.Combine(baseDir, "turbotoken");
            }
        }

        /// <summary>
        /// Ensure a rank file is downloaded and cached. Returns the file path.
        /// </summary>
        public static async Task<string> EnsureRankFileAsync(string name, CancellationToken ct = default)
        {
            var spec = Registry.GetEncodingSpec(name);
            var uri = new Uri(spec.RankFileUrl);
            var fileName = Path.GetFileName(uri.AbsolutePath);
            var localPath = Path.Combine(CacheDir, fileName);

            if (File.Exists(localPath))
                return localPath;

            Directory.CreateDirectory(CacheDir);

            var data = await HttpClient.GetByteArrayAsync(spec.RankFileUrl).ConfigureAwait(false);
            var tempPath = localPath + ".tmp";
            File.WriteAllBytes(tempPath, data);
            File.Move(tempPath, localPath);

            return localPath;
        }

        /// <summary>
        /// Read a rank file's contents, downloading if necessary.
        /// </summary>
        public static async Task<byte[]> ReadRankFileAsync(string name, CancellationToken ct = default)
        {
            var filePath = await EnsureRankFileAsync(name, ct).ConfigureAwait(false);
            return File.ReadAllBytes(filePath);
        }
    }
}
