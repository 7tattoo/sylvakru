#include "flac_decoder.h"

#include <cassert>

int main() {
    sylvakru::FlacDecoder decoder;
    const auto result = decoder.open("missing.flac");
    assert(!result.ok());
    assert(result.error == sylvakru::FlacError::kOpenFailed);
    return 0;
}
