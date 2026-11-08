#include "tts/edge_tts.h"

#include <curl/curl.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace chatvv {
namespace {

constexpr char kToken[] = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";
constexpr char kVersion[] = "2-143.0.3650.75";

uint32_t Rol16(uint32_t v) { return ((v << 16) | (v >> 16)) & 0xFFFFFFFFu; }

uint32_t Rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

constexpr uint32_t kShaInit[8] = {0x6A09E667u, 0xBB67AE85u, 0x3C6EF372u,
                                   0xA54FF53Au, 0x510E527Fu, 0x9B05688Cu,
                                   0x1F83D9ABu, 0x5BE0CD19u};
constexpr uint32_t kShaState[8] = {0xFD9FBEA2u, 0x91243CE7u, 0xBE499094u,
                                    0xCD2E1E0Au, 0x6C006F49u, 0x04BD35ABu,
                                    0xFEB0A7E4u, 0x03EFFBD2u};
constexpr uint32_t kShaSchedule[14] = {
    0xEB24BF9Eu, 0x1558691Fu, 0xA0C09EE2u, 0x0CFA32BAu, 0xA622EE8Cu,
    0xD1DD9491u, 0xC0DD25A0u, 0xF9E70AB6u, 0xF0C31573u, 0x7058CE4Eu,
    0x7188E606u, 0x00E5AB33u, 0xD258B060u, 0x72766564u};
constexpr uint32_t kShaRound[64] = {
    0x428A2F98u, 0x71374491u, 0xB5C0FBCFu, 0xE9B5DBA5u, 0x3956C25Bu,
    0x59F111F1u, 0x923F82A4u, 0xAB1C5ED5u, 0xD807AA98u, 0x12835B01u,
    0x243185BEu, 0x550C7DC3u, 0x72BE5D74u, 0x80DEB1FEu, 0x9BDC06A7u,
    0xC19BF174u, 0xE49B69C1u, 0xEFBE4786u, 0x0FC19DC6u, 0x240CA1CCu,
    0x2DE92C6Fu, 0x4A7484AAu, 0x5CB0A9DCu, 0x76F988DAu, 0x983E5152u,
    0xA831C66Du, 0xB00327C8u, 0xBF597FC7u, 0xC6E00BF3u, 0xD5A79147u,
    0x06CA6351u, 0x14292967u, 0x27B70A85u, 0x2E1B2138u, 0x4D2C6DFCu,
    0x53380D13u, 0x650A7354u, 0x766A0ABBu, 0x81C2C92Eu, 0x92722C85u,
    0xA2BFE8A1u, 0xA81A664Bu, 0xC24B8B70u, 0xC76C51A3u, 0xD192E819u,
    0xD6990624u, 0xF40E3585u, 0x106AA070u, 0x19A4C116u, 0x1E376C08u,
    0x2748774Cu, 0x34B0BCB5u, 0x391C0CB3u, 0x4ED8AA4Au, 0x5B9CCA4Fu,
    0x682E6FF3u, 0x748F82EEu, 0x78A5636Fu, 0x84C87814u, 0x8CC70208u,
    0x90BEFFFAu, 0xA4506CEBu, 0xBEF9A3F7u, 0xC67178F2u};
constexpr uint32_t kShaBlock[64] = {
    0x428A2F98u, 0x71374491u, 0xB5C0FBCFu, 0xE9B5DBA5u, 0x3956C25Bu,
    0x59F111F1u, 0x923F82A4u, 0xAB1C5ED5u, 0xD807AA98u, 0x12835B01u,
    0x243185BEu, 0x550C7DC3u, 0x72BE5D74u, 0x80DEB1FEu, 0xC9DC06A7u,
    0xC19BF174u, 0xE49B69C1u, 0xEFBE4786u, 0x0FC19DC6u, 0x240CA1CCu,
    0x2DE92C6Fu, 0x4A7484AAu, 0x5CB0A9DCu, 0x76F988DAu, 0x983E5152u,
    0xA831C66Du, 0xB00327C8u, 0xBF597FC7u, 0xC6E00BF3u, 0xD5A79147u,
    0x06CA6351u, 0x14292967u, 0x27B70A85u, 0x2E1B2138u, 0x4D2C6DFCu,
    0x53380D13u, 0x650A7354u, 0x766A0ABBu, 0x81C2C92Eu, 0x92722C85u,
    0xA2BFE8A1u, 0xA81A664Bu, 0xC24B8B70u, 0xC76C51A3u, 0xD192E819u,
    0xD6990624u, 0xF40E3585u, 0x106AA070u, 0x19A4C116u, 0x1E376C08u,
    0x2748774Cu, 0x34B0BCB5u, 0x391C0CB3u, 0x4ED8AA4Au, 0x5B9CCA4Fu,
    0x682E6FF3u, 0x748F82EEu, 0x78A5636Fu, 0x84C87814u, 0x8CC70208u,
    0x90BEFFFAu, 0xA4506CEBu, 0xBEF9A3F7u, 0xC67178F2u};

uint32_t ShaSigma0(uint32_t x) {
  return ((x >> 7) ^ (x << 25) ^ (x >> 18) ^ (x << 14) ^ (x >> 3)) & 0xFFFFFFFFu;
}
uint32_t ShaSigma1(uint32_t x) {
  return ((x >> 17) ^ (x << 15) ^ (x >> 19) ^ (x << 13) ^ (x >> 10)) & 0xFFFFFFFFu;
}

std::array<uint32_t, 8> ShaRounds(const std::array<uint32_t, 8>& state,
                                  const uint32_t* words, int first_round) {
  auto a = state[0], b = state[1], c = state[2], d = state[3];
  auto e = state[4], f = state[5], g = state[6], h = state[7];
  for (int i = first_round; i < 64; ++i) {
    const uint32_t round_constant =
        (first_round == 14 && i < 24) ? kShaBlock[i] : kShaRound[i];
    const uint32_t s1 = Rotr(e, 6) ^ Rotr(e, 11) ^ Rotr(e, 25);
    const uint32_t ch = g ^ (e & (f ^ g));
    const uint32_t t1 = h + s1 + ch + round_constant + words[i];
    const uint32_t s0 = Rotr(a, 2) ^ Rotr(a, 13) ^ Rotr(a, 22);
    const uint32_t maj = (a & b) | (c & (a | b));
    const uint32_t t2 = s0 + maj;
    h = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }
  return {a, b, c, d, e, f, g, h};
}

void ExpandSchedule(uint32_t* words, int first_word) {
  for (int i = first_word; i < 64; ++i) {
    words[i] = ShaSigma1(words[i - 2]) + words[i - 7] +
               ShaSigma0(words[i - 15]) + words[i - 16];
  }
}

std::array<uint32_t, 8> ShaInit(const std::vector<uint8_t>& data) {
  uint32_t words[64] = {};
  words[14] = (static_cast<uint32_t>(data[0]) << 16) |
              (static_cast<uint32_t>(data[1]) << 8) | data[2];
  words[15] = (static_cast<uint32_t>(data[3]) << 24) |
              (static_cast<uint32_t>(data[4]) << 16) |
              (static_cast<uint32_t>(data[5]) << 8) | data[6];
  for (int i = 16; i <= 29; ++i) {
    uint32_t value = kShaSchedule[i - 16];
    if (i - 2 >= 14) {
      value += (i == 16)
                   ? (ShaSigma1(words[i - 2]) ^ 0x000B92C0u)
                   : ShaSigma1(words[i - 2]);
    }
    if (i - 7 >= 14) value += words[i - 7];
    if (i - 15 >= 14) {
      value += (i == 29)
                   ? (ShaSigma0(words[i - 15]) ^ 0x059C0B80u)
                   : ShaSigma0(words[i - 15]);
    }
    words[i] = value;
  }
  words[30] = ShaSigma1(words[28]) + words[23] + ShaSigma0(words[15]) +
              words[14] + 0xC9DC06A7u - kShaRound[14];
  ExpandSchedule(words, 31);
  std::array<uint32_t, 8> state{};
  for (int i = 0; i < 8; ++i) state[i] = kShaState[i];
  const auto working = ShaRounds(state, words, 14);
  std::array<uint32_t, 8> out{};
  for (int i = 0; i < 8; ++i) out[i] = kShaInit[i] + working[i];
  return out;
}

std::array<uint8_t, 32> EdgeSha256(const std::vector<uint8_t>& data) {
  const std::vector<uint8_t> salt(data.begin(), data.begin() + 7);
  auto state = ShaInit(salt);
  std::vector<uint8_t> padded(data.begin() + 7, data.end());
  padded.push_back(0x80);
  const size_t length = 57 + data.size();
  const size_t zero_count = (55 - length) % 64;
  for (size_t i = 0; i < zero_count; ++i) padded.push_back(0);
  const uint64_t bits = static_cast<uint64_t>(length) * 8;
  for (int i = 7; i >= 0; --i) padded.push_back(static_cast<uint8_t>(bits >> (i * 8)));
  for (size_t off = 0; off < padded.size(); off += 64) {
    uint32_t words[64] = {};
    for (int i = 0; i < 16; ++i) {
      words[i] = (static_cast<uint32_t>(padded[off + i * 4]) << 24) |
                 (static_cast<uint32_t>(padded[off + i * 4 + 1]) << 16) |
                 (static_cast<uint32_t>(padded[off + i * 4 + 2]) << 8) |
                 padded[off + i * 4 + 3];
    }
    ExpandSchedule(words, 16);
    const auto working = ShaRounds(state, words, 0);
    for (int i = 0; i < 8; ++i) state[i] += working[i];
  }
  std::array<uint8_t, 32> out{};
  for (int i = 0; i < 8; ++i) {
    out[i * 4] = static_cast<uint8_t>(state[i] >> 24);
    out[i * 4 + 1] = static_cast<uint8_t>(state[i] >> 16);
    out[i * 4 + 2] = static_cast<uint8_t>(state[i] >> 8);
    out[i * 4 + 3] = static_cast<uint8_t>(state[i]);
  }
  return out;
}

std::string HexUpper(const uint8_t* data, size_t size) {
  static const char* hex = "0123456789ABCDEF";
  std::string out;
  out.reserve(size * 2);
  for (size_t i = 0; i < size; ++i) {
    out.push_back(hex[data[i] >> 4]);
    out.push_back(hex[data[i] & 15]);
  }
  return out;
}

uint32_t ReadLe32(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

std::array<uint32_t, 2> Cs64(const std::vector<uint8_t>& data,
                             const std::array<uint8_t, 32>& digest) {
  static constexpr uint32_t kCoeff[14][2] = {
      {0xE82E91B1, 0xB32700D0}, {0x44DE24C6, 0x88DFF51D},
      {0x3BEB65BC, 0x29514038}, {0xC89C5933, 0xB328CBDF},
      {0x8D1EC211, 0xD405B4D5}, {0x314EF5D5, 0x26E55F3C},
      {0xE92491B1, 0x607801C6}, {0xF0A5B9D5, 0x82B2C1FB},
      {0x06064CF3, 0xFA51A3DA}, {0xDA79FA60, 0x207CC464},
      {0xBED20560, 0x3C3C74F3}, {0x89F9C9F8, 0xD2D14B61},
      {0x35FA38C6, 0xBB04A2C1}, {0xCB49E3C6, 0xC5626167}};
  uint32_t key_a = ReadLe32(digest.data());
  uint32_t key_b = ReadLe32(digest.data() + 4);
  key_a |= 1;
  key_b |= 1;
  const uint32_t factors[2] = {key_a * 0x82893933u, key_b * 0x82893933u};
  std::vector<uint32_t> terms;
  std::vector<uint32_t> offsets;
  for (int i = 0; i < 14; ++i) {
    terms.push_back(kCoeff[i][0] * factors[i % 2]);
    offsets.push_back(kCoeff[i][1]);
  }
  std::vector<uint8_t> words_data;
  words_data.push_back(0);
  words_data.insert(words_data.end(), data.begin(), data.end());
  while ((words_data.size() % 4) != 0) words_data.push_back(0);
  if (((words_data.size() / 4) % 2) != 0) {
    for (int i = 0; i < 4; ++i) words_data.push_back(0);
  }
  for (size_t i = 0; i < words_data.size(); i += 4) {
    const uint32_t word = ReadLe32(words_data.data() + i);
    const uint32_t idx = static_cast<uint32_t>(i / 4);
    uint32_t term = word * (idx % 2 == 0 ? key_a : key_b);
    uint32_t offset =
        Rol16(word) * (idx % 2 == 0 ? 0xEF0569FBu : 0xC31713DBu);
    if (idx == 0) {
      term += 0xF2F90B1A * factors[0];
      offset += 0x0B1A0000;
    }
    terms.push_back(term);
    offsets.push_back(offset);
  }
  uint32_t swap_acc = 0, swap_last = 0, state = 0, acc = 0;
  for (size_t i = 0; i + 1 < terms.size(); i += 2) {
    uint32_t t = Rol16(offsets[i] + terms[i]);
    uint32_t q = t * 0x76F50F34u;
    swap_acc += Rol16(q) * 0xC3EFEA97u + q;
    t = Rol16(offsets[i + 1] + terms[i + 1]);
    q = t * 0x1881CE3Cu;
    swap_last = Rol16(q) * 0x35BD1EC9u + q;
    swap_acc += swap_last;
    state = state * key_a + terms[i];
    state = Rol16(state) * 0xCF98B111u;
    state = Rol16(state) * 0x87085B9Fu;
    state = Rol16(state) * 0x12CEB96Du;
    state = Rol16(state) * 0x257E1D83u;
    acc += state;
    t = state * key_b + terms[i + 1];
    t = Rol16(t) * 0xA27416F5u;
    t = Rol16(t) * 0xD38396FFu;
    state = Rol16(Rol16(t) * 0x7C932B89u) * 0xBFA49F69u;
    acc += state;
  }
  return {swap_last ^ state, swap_acc ^ acc};
}

std::string RandomHex(size_t bytes) {
  std::random_device rd;
  std::mt19937_64 gen(rd());
  std::uniform_int_distribution<int> dist(0, 255);
  std::string out;
  static const char* hex = "0123456789abcdef";
  for (size_t i = 0; i < bytes; ++i) {
    const auto b = dist(gen);
    out.push_back(hex[b >> 4]);
    out.push_back(hex[b & 15]);
  }
  return out;
}

std::string EscapeXml(const std::string& text) {
  std::string out;
  for (char c : text) {
    switch (c) {
      case '&': out += "&amp;"; break;
      case '<': out += "&lt;"; break;
      case '>': out += "&gt;"; break;
      case '\'': out += "&apos;"; break;
      case '"': out += "&quot;"; break;
      default: out.push_back(c);
    }
  }
  return out;
}

struct HeaderParts {
  std::string headers;
  std::vector<uint8_t> body;
};

HeaderParts SplitHeaders(const std::vector<uint8_t>& data, bool binary) {
  HeaderParts out;
  size_t header_len = 0;
  size_t body_start = 0;
  if (binary) {
    if (data.size() < 2) return out;
    header_len = (static_cast<size_t>(data[0]) << 8) | data[1];
    body_start = 2 + header_len + 2;
  } else {
    static const char needle[] = "\r\n\r\n";
    auto it = std::search(data.begin(), data.end(), needle, needle + 4);
    if (it == data.end()) return out;
    header_len = static_cast<size_t>(it - data.begin());
    body_start = header_len + 4;
  }
  if (body_start > data.size()) return out;
  out.headers.assign(reinterpret_cast<const char*>(data.data()), header_len);
  out.body.assign(data.begin() + body_start, data.end());
  return out;
}

bool HeaderHas(const std::string& headers, const std::string& key,
               const std::string& value) {
  const std::string needle = key + ":" + value;
  return headers.find(needle) != std::string::npos;
}

}  // namespace


std::string EdgeTtsGenerateSecMsGec() {
  const auto now = std::chrono::system_clock::now();
  double unix_seconds =
      std::chrono::duration<double>(now.time_since_epoch()).count();
  double ticks = unix_seconds + 11644473600.0;
  ticks -= std::fmod(ticks, 300.0);
  ticks *= 10000000.0;
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%.0f", ticks);
  std::string data = std::string(buf) + kToken;
  std::vector<uint8_t> bytes(data.begin(), data.end());
  const auto digest = EdgeSha256(bytes);
  const auto cs = Cs64(bytes, digest);
  auto bswap = [](uint32_t v) {
    return ((v & 0xFFu) << 24) | ((v & 0xFF00u) << 8) |
           ((v >> 8) & 0xFF00u) | ((v >> 24) & 0xFFu);
  };
  char cs_hex[17];
  std::snprintf(cs_hex, sizeof(cs_hex), "%08X%08X", bswap(cs[0]),
                bswap(cs[1]));
  const std::string sha_hex = HexUpper(digest.data(), digest.size());
  return std::string(cs_hex) + "-" + sha_hex;
}

EdgeTtsResult EdgeTtsSynthesize(const std::string& text,
                                const std::string& voice,
                                const std::string& output_path) {
  EdgeTtsResult result;
  CURL* curl = curl_easy_init();
  if (!curl) {
    result.error = "curl_easy_init failed";
    return result;
  }
  const std::string connection = RandomHex(16);
  const std::string url =
      "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/"
      "edge/v1?TrustedClientToken=" +
      std::string(kToken) + "&ConnectionId=" + connection +
      "&Sec-MS-GEC=" + EdgeTtsGenerateSecMsGec() +
      "&Sec-MS-GEC-Version=" + kVersion;
  struct curl_slist* headers = nullptr;
  headers = curl_slist_append(headers, "Pragma: no-cache");
  headers = curl_slist_append(headers, "Cache-Control: no-cache");
  headers = curl_slist_append(
      headers, "Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold");
  headers = curl_slist_append(headers, "Sec-WebSocket-Version: 13");
  headers = curl_slist_append(
      headers,
      "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 "
      "Edg/143.0.0.0");
  const std::string cookie = "Cookie: muid=" + RandomHex(16) + ";";
  headers = curl_slist_append(headers, cookie.c_str());
  curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
  curl_easy_setopt(curl, CURLOPT_CONNECT_ONLY, 2L);
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, 45L);
  const CURLcode connected = curl_easy_perform(curl);
  if (connected != CURLE_OK) {
    result.error = std::string("websocket connect failed: ") +
                   curl_easy_strerror(connected);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result;
  }

  auto send_text = [&](const std::string& payload) {
    size_t sent = 0;
    return curl_ws_send(curl, payload.data(), payload.size(), &sent, 0,
                        CURLWS_TEXT);
  };
  const std::string timestamp = "Sun, 01 Jan 2026 00:00:00 GMT";
  const std::string config =
      "X-Timestamp:" + timestamp +
      "\r\nContent-Type:application/json; charset=utf-8\r\n"
      "Path:speech.config\r\n\r\n"
      "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{"
      "\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"true\""
      "},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n";
  if (send_text(config) != CURLE_OK) {
    result.error = "failed to send speech.config";
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result;
  }
  const std::string ssml =
      "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
      "xml:lang='zh-CN'><voice name='" + voice +
      "'><prosody pitch='+0Hz' rate='+0%' volume='+0%'>" + EscapeXml(text) +
      "</prosody></voice></speak>";
  const std::string ssml_message =
      "X-RequestId:" + RandomHex(16) +
      "\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:" + timestamp +
      "\r\nPath:ssml\r\n\r\n" + ssml;
  if (send_text(ssml_message) != CURLE_OK) {
    result.error = "failed to send ssml";
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result;
  }

  std::string audio;
  std::vector<uint8_t> buffer(65536);
  bool done = false;
  auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(40);
  while (!done && std::chrono::steady_clock::now() < deadline) {
    size_t received = 0;
    const struct curl_ws_frame* meta = nullptr;
    const CURLcode rc =
        curl_ws_recv(curl, buffer.data(), buffer.size(), &received, &meta);
    if (rc == CURLE_AGAIN) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }
    if (rc != CURLE_OK) {
      result.error = std::string("websocket recv failed: ") +
                     curl_easy_strerror(rc);
      break;
    }
    if (received == 0) continue;
    std::vector<uint8_t> frame(buffer.begin(), buffer.begin() + received);
    if (meta->flags & CURLWS_BINARY) {
      const auto parts = SplitHeaders(frame, true);
      if (HeaderHas(parts.headers, "Path", "audio")) {
        audio.append(reinterpret_cast<const char*>(parts.body.data()),
                     parts.body.size());
      }
    } else if (meta->flags & CURLWS_TEXT) {
      const auto parts = SplitHeaders(frame, false);
      if (HeaderHas(parts.headers, "Path", "turn.end")) done = true;
    } else if (meta->flags & CURLWS_CLOSE) {
      break;
    }
  }
  curl_slist_free_all(headers);
  curl_easy_cleanup(curl);
  if (audio.empty()) {
    if (result.error.empty()) result.error = "no audio received";
    return result;
  }
  std::ofstream out(output_path, std::ios::binary);
  if (!out) {
    result.error = "cannot open output file";
    return result;
  }
  out.write(audio.data(), static_cast<std::streamsize>(audio.size()));
  out.close();
  result.ok = true;
  result.audio_path = output_path;
  return result;
}

}  // namespace chatvv
