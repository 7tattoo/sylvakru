#pragma once

#include <string>

namespace sylvakru {

enum class FlacError {
    kNone,
    kOpenFailed,
    kInvalidStream,
    kUnsupportedFormat,
    kDecodeFailed,
    kSeekFailed,
    kInvalidBuffer,
};

struct FlacResult {
    FlacError error = FlacError::kNone;
    std::string message;

    bool ok() const { return error == FlacError::kNone; }
};

class FlacDecoder {
public:
    FlacResult open(const std::string& path);
};

}  // namespace sylvakru
