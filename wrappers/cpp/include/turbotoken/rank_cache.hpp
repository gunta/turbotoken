#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace turbotoken {

std::filesystem::path cache_dir();
std::filesystem::path ensure_rank_file(const std::string& name);
std::vector<uint8_t> read_rank_file(const std::string& name);

} // namespace turbotoken
