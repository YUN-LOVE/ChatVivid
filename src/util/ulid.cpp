#include "util/ulid.h"
#include "util/util.h"

#include <chrono>
#include <mutex>
#include <random>

namespace chatvv {
namespace {

constexpr char kEnc[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

std::mutex g_mu;
std::mt19937_64 g_rng{std::random_device{}()};

}  // namespace

std::string ulid() {
  const uint64_t ts = static_cast<uint64_t>(now_ms());

  uint8_t data[16];
  for (int i = 0; i < 6; ++i) {
    data[i] = static_cast<uint8_t>((ts >> (8 * (5 - i))) & 0xFF);
  }

  uint64_t r1 = 0;
  uint64_t r2 = 0;
  {
    std::lock_guard lock(g_mu);
    r1 = g_rng();
    r2 = g_rng();
  }
  for (int i = 0; i < 8; ++i) {
    data[6 + i] = static_cast<uint8_t>((r1 >> (8 * (7 - i))) & 0xFF);
  }
  data[14] = static_cast<uint8_t>((r2 >> 56) & 0xFF);
  data[15] = static_cast<uint8_t>((r2 >> 48) & 0xFF);

  // 128 bits are encoded as 26 base32 chars: 130 bits with two leading zeros.
  std::string out(26, '0');
  for (int i = 0; i < 26; ++i) {
    int value = 0;
    for (int b = 0; b < 5; ++b) {
      const int bit_index = i * 5 + b - 2;
      int bit = 0;
      if (bit_index >= 0) {
        bit = (data[bit_index / 8] >> (7 - (bit_index % 8))) & 1;
      }
      value = (value << 1) | bit;
    }
    out[i] = kEnc[value];
  }
  return out;
}

}  // namespace chatvv
