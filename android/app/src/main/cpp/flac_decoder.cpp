#include "flac_decoder.h"

#include <FLAC/stream_decoder.h>

#include <cstdio>

namespace sylvakru {

FlacResult FlacDecoder::open(const std::string& path) {
    FILE* file = std::fopen(path.c_str(), "rb");
    if (file == nullptr) {
        return {FlacError::kOpenFailed, "Failed to open FLAC file."};
    }
    std::fclose(file);
    return {};
}

}  // namespace sylvakru
