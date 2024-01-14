#pragma once
#include "generator.hpp"
#include <chrono>


// A yielding type is a generator that returns an optional of the underlying type.
// If it yields nullopt, then the next nif execution will be scheduled, otherwise, that thing is returned to the caller.
template <typename T>
using yielding = cppcoro::generator<std::optional<T>>;


template <typename T>
struct is_yielding : std::false_type
{ };


template <typename T>
struct is_yielding<cppcoro::generator<std::optional<T>>> : std::true_type
{ };


template <typename T>
inline constexpr bool is_yielding_v = is_yielding<T>::value;


// a simple timer for knowing when to yield back to the erlang runtime
struct yielding_timer
{
    std::chrono::time_point<std::chrono::steady_clock> start_time;

    yielding_timer()
    {
        this->reset();
    }

    void reset()
    {
        this->start_time = std::chrono::steady_clock::now();
    }

    bool times_up() const
    {
        using namespace std;
        return chrono::duration_cast<chrono::microseconds>(chrono::steady_clock::now() - start_time).count() >= 990;
    }
};


using yielding_resource_t = resource<yielding<int>>;
