#pragma once

#include <string>

namespace chatvv {

// ULID: 26 chars, Crockford base32, lexicographically sortable by time.
std::string ulid();

}  // namespace chatvv
