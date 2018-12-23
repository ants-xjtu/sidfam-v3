#include <functional>
#include <utility>
#include <vector>

namespace std {
    template<typename T, typename U> struct hash<pair<T, U>> {
        typedef pair<T, U> argument_type;
        typedef std::size_t result_type;
        result_type operator()(argument_type const &p) const noexcept {
            return hash<T>()(p.first) ^ (hash<U>()(p.second) << 1);
        }
    };

    template<typename T> struct hash<vector<T>> {
        typedef vector<T> argument_type;
        typedef std::size_t result_type;
        result_type operator()(argument_type const &p) const noexcept {
            std::size_t len = p.size(), result = 0;
            for (std::size_t i = 0; i < len; i++) {
                return hash<T>()(p[i]) ^ (result << 1);
            }
            return result;
        }
    };
}
