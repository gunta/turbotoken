#include "turbotoken/rank_cache.hpp"
#include "turbotoken/error.hpp"
#include "turbotoken/registry.hpp"

#include <cstdlib>
#include <fstream>

namespace turbotoken {

std::filesystem::path cache_dir() {
    // Use $TURBOTOKEN_CACHE_DIR, or $XDG_CACHE_HOME/turbotoken, or ~/.cache/turbotoken
    const char* env = std::getenv("TURBOTOKEN_CACHE_DIR");
    if (env && *env) {
        return std::filesystem::path(env);
    }

    const char* xdg = std::getenv("XDG_CACHE_HOME");
    if (xdg && *xdg) {
        return std::filesystem::path(xdg) / "turbotoken";
    }

    const char* home = std::getenv("HOME");
    if (!home || !*home) {
#ifdef _WIN32
        home = std::getenv("USERPROFILE");
#endif
    }
    if (home && *home) {
        return std::filesystem::path(home) / ".cache" / "turbotoken";
    }

    return std::filesystem::path(".cache") / "turbotoken";
}

static void download_file(const std::string& url, const std::filesystem::path& dest) {
    // Use system curl for portability
    auto parent = dest.parent_path();
    if (!parent.empty()) {
        std::filesystem::create_directories(parent);
    }

    std::string tmp = dest.string() + ".tmp";
    std::string cmd = "curl -fsSL -o \"" + tmp + "\" \"" + url + "\"";
    int rc = std::system(cmd.c_str());
    if (rc != 0) {
        std::filesystem::remove(tmp);
        throw DownloadError("Failed to download " + url + " (curl exit code " + std::to_string(rc) + ")");
    }
    std::filesystem::rename(tmp, dest);
}

std::filesystem::path ensure_rank_file(const std::string& name) {
    const auto& spec = get_encoding_spec(name);
    auto dir = cache_dir();
    auto path = dir / (name + ".tiktoken");

    if (std::filesystem::exists(path)) {
        return path;
    }

    download_file(spec.rank_file_url, path);
    return path;
}

std::vector<uint8_t> read_rank_file(const std::string& name) {
    auto path = ensure_rank_file(name);

    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) {
        throw DownloadError("Cannot open rank file: " + path.string());
    }

    auto size = f.tellg();
    f.seekg(0, std::ios::beg);

    std::vector<uint8_t> data(static_cast<size_t>(size));
    if (!f.read(reinterpret_cast<char*>(data.data()), size)) {
        throw DownloadError("Failed to read rank file: " + path.string());
    }

    return data;
}

} // namespace turbotoken
