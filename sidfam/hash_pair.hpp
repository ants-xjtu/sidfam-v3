#include <functional>
#include <utility>

namespace std {
    template<typename T, typename U> struct hash<pair<T, U>> {
        typedef pair<T, U> argument_type;
        typedef std::size_t result_type;
        result_type operator()(argument_type const &p) const noexcept {
            return hash<T>()(p.first) ^ (hash<U>()(p.second) << 1);
        }
    };
}
