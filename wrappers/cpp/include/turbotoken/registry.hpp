#pragma once

#include <string>
#include <unordered_map>
#include <vector>

namespace turbotoken {

struct EncodingSpec {
    std::string name;
    std::string rank_file_url;
    std::string pat_str;
    std::unordered_map<std::string, int> special_tokens;
    int n_vocab;
};

const EncodingSpec& get_encoding_spec(const std::string& name);
std::string model_to_encoding(const std::string& model);
std::vector<std::string> list_encoding_names();

} // namespace turbotoken
