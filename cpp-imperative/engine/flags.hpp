#pragma once
#include <stdexcept>
#include <functional>
#include <bitset>

namespace flags {
    template <size_t N>
    class flags {
        public:
            flags() noexcept;

            // flip-copy and flip-move constructors
            //flags(const flags & source, const bool _flip) noexcept;
            //flags(const flags && source, const bool _flip) noexcept;

            // default the big 5
            flags(const flags & source) noexcept = default;
            flags & operator=(const flags & source) noexcept = default;
            virtual ~flags() noexcept = default;
            flags & operator=(flags && source) noexcept = default;
            flags(flags && source) noexcept = default;

            // accessors
            bool test(const size_t pos) const;
            flags & set(const size_t pos, const bool value=true);

            // flips in place
            void flip();
            size_t get_hash() const;

        private:
            std::bitset<N> _flags;
            bool flipped;
    };
}

template <size_t N>
flags::flags<N>::flags() noexcept
{
    flipped=false;
}

/*
template <size_t N>
flags::flags<N>::flags(const flags & source, const bool _flip) noexcept : _flags(source._flags)
{
    flipped=source.flipped;
    if(_flip) flip();
}

template <size_t N>
flags::flags<N>::flags(const flags && source, const bool _flip) noexcept : _flags(std::move(source._flags))
{
    flipped=source.flipped;
    if(_flip) flip();
}
*/

template <size_t N>
bool flags::flags<N>::test(const size_t pos) const
{
    //if (pos>=N) throw std::out_of_range("Flags out of range.");
    if (flipped)
        return _flags.test(N-1-pos);
    else
        return _flags.test(pos);
}

template <size_t N>
flags::flags<N> & flags::flags<N>::set(const size_t pos, const bool value)
{
    //if (pos>=N) throw std::out_of_range("Flags out of range.");
    if (flipped)
        _flags.set(N-1-pos, value);
    else
        _flags.set(pos, value);
    return *this;
}

template <size_t N>
void flags::flags<N>::flip()
{
    flipped = !flipped;
}

template <size_t N>
size_t flags::flags<N>::get_hash() const
{
    size_t _hash = std::hash<std::bitset<N>>()(_flags);
    // Simple hash combine using XOR and shift (similar to boost::hash_combine)
    _hash ^= std::hash<bool>()(flipped) + 0x9e3779b9 + (_hash << 6) + (_hash >> 2);
    return _hash;
}
