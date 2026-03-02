#pragma once

#include <stdexcept>
#include <string>

namespace turbotoken {

class TurbotokenError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class EncodingError : public TurbotokenError {
public:
    using TurbotokenError::TurbotokenError;
};

class DecodingError : public TurbotokenError {
public:
    using TurbotokenError::TurbotokenError;
};

class InvalidEncodingError : public TurbotokenError {
public:
    using TurbotokenError::TurbotokenError;
};

class DownloadError : public TurbotokenError {
public:
    using TurbotokenError::TurbotokenError;
};

} // namespace turbotoken
