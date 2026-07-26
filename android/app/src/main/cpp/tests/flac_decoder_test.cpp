#include "flac_decoder.h"

#include <cassert>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#ifndef SYLVAKRU_FLAC_TESTDATA_DIR
#error "SYLVAKRU_FLAC_TESTDATA_DIR is required"
#endif

namespace {

std::string testData(const char* name) {
    return std::string(SYLVAKRU_FLAC_TESTDATA_DIR) + "/" + name;
}

int32_t readSignedSample(const std::vector<uint8_t>& bytes, size_t offset, int sample_bytes) {
    uint32_t value = 0;
    for (int index = 0; index < sample_bytes; ++index) {
        value |= static_cast<uint32_t>(bytes[offset + index]) << (index * 8);
    }
    const int shift = 32 - sample_bytes * 8;
    return static_cast<int32_t>(value << shift) >> shift;
}

std::vector<int32_t> readReference(const char* name, int sample_bytes) {
    std::ifstream input(testData(name), std::ios::binary);
    assert(input.good());
    const std::vector<uint8_t> bytes(
        (std::istreambuf_iterator<char>(input)),
        std::istreambuf_iterator<char>());
    std::vector<int32_t> samples;
    for (size_t offset = 0; offset + sample_bytes <= bytes.size(); offset += sample_bytes) {
        samples.push_back(readSignedSample(bytes, offset, sample_bytes));
    }
    return samples;
}

void verifiesMissingFile() {
    sylvakru::FlacDecoder decoder;
    const auto result = decoder.open(testData("missing.flac"));
    assert(!result.ok());
    assert(result.error == sylvakru::FlacError::kOpenFailed);
}

void verifies16BitSamples() {
    sylvakru::FlacDecoder decoder;
    assert(decoder.open(testData("pcm16_stereo.flac")).ok());
    const auto info = decoder.streamInfo();
    assert(info.sample_rate == 48000);
    assert(info.channels == 2);
    assert(info.valid_bits_per_sample == 16);
    assert(info.total_frames == 256);

    std::vector<int32_t> decoded(info.total_frames * info.channels);
    const auto read = decoder.readFrames(decoded.data(), 256);
    assert(read.ok());
    assert(read.frames == 256);
    assert(read.end_of_stream);
    assert(decoded == readReference("pcm16_stereo.raw", 2));
}

void verifies24BitSamples() {
    sylvakru::FlacDecoder decoder;
    assert(decoder.open(testData("pcm24_stereo.flac")).ok());
    const auto info = decoder.streamInfo();
    assert(info.sample_rate == 48000);
    assert(info.channels == 2);
    assert(info.valid_bits_per_sample == 24);
    assert(info.total_frames == 256);

    std::vector<int32_t> decoded(info.total_frames * info.channels);
    const auto read = decoder.readFrames(decoded.data(), 256);
    assert(read.ok());
    assert(read.frames == 256);
    assert(read.end_of_stream);
    assert(decoded == readReference("pcm24_stereo.raw", 3));
    bool has_nonzero_low_byte = false;
    for (const int32_t sample : decoded) {
        has_nonzero_low_byte |= (sample & 0xff) != 0;
    }
    assert(has_nonzero_low_byte);
}

void verifiesChunkedReads() {
    sylvakru::FlacDecoder decoder;
    assert(decoder.open(testData("pcm24_stereo.flac")).ok());
    const auto info = decoder.streamInfo();

    std::vector<int32_t> decoded;
    std::vector<int32_t> chunk(100 * info.channels);
    while (true) {
        const auto read = decoder.readFrames(chunk.data(), 100);
        assert(read.ok());
        decoded.insert(
            decoded.end(),
            chunk.begin(),
            chunk.begin() + read.frames * info.channels);
        if (read.end_of_stream) {
            break;
        }
        assert(read.frames > 0);
    }
    assert(decoded == readReference("pcm24_stereo.raw", 3));

    const auto after_end = decoder.readFrames(chunk.data(), 100);
    assert(after_end.ok());
    assert(after_end.frames == 0);
    assert(after_end.end_of_stream);
}

void verifiesSeek() {
    sylvakru::FlacDecoder decoder;
    assert(decoder.open(testData("pcm24_stereo.flac")).ok());
    const auto info = decoder.streamInfo();
    const auto reference = readReference("pcm24_stereo.raw", 3);

    assert(decoder.seekToFrame(128).ok());
    std::vector<int32_t> tail(128 * info.channels);
    const auto tail_read = decoder.readFrames(tail.data(), 128);
    assert(tail_read.ok());
    assert(tail_read.frames == 128);
    assert(
        std::vector<int32_t>(
            reference.begin() + 128 * info.channels,
            reference.end()) == tail);

    assert(decoder.seekToFrame(0).ok());
    std::vector<int32_t> full(256 * info.channels);
    const auto full_read = decoder.readFrames(full.data(), 256);
    assert(full_read.ok());
    assert(full_read.frames == 256);
    assert(full == reference);
}

void verifiesTruncatedFileFailsLoudly() {
    sylvakru::FlacDecoder decoder;
    const auto opened = decoder.open(testData("pcm24_stereo_truncated.flac"));
    if (!opened.ok()) {
        return;
    }
    std::vector<int32_t> decoded(256 * decoder.streamInfo().channels);
    const auto read = decoder.readFrames(decoded.data(), 256);
    assert(!read.ok() || read.frames < 256);
}

}  // namespace

int main() {
    std::fprintf(stderr, "verifiesMissingFile\n");
    verifiesMissingFile();
    std::fprintf(stderr, "verifies16BitSamples\n");
    verifies16BitSamples();
    std::fprintf(stderr, "verifies24BitSamples\n");
    verifies24BitSamples();
    std::fprintf(stderr, "verifiesChunkedReads\n");
    verifiesChunkedReads();
    std::fprintf(stderr, "verifiesSeek\n");
    verifiesSeek();
    std::fprintf(stderr, "verifiesTruncatedFileFailsLoudly\n");
    verifiesTruncatedFileFailsLoudly();
    std::fprintf(stderr, "all tests passed\n");
    return 0;
}
