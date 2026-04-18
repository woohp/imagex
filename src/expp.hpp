#pragma once

// Combined expp bundle

#include <algorithm>
#include <chrono>
#include <concepts>
#include <coroutine>
#include <cstdint>
#include <erl_nif.h>
#include <exception>
#include <expected>
#include <functional>
#include <iostream>
#include <iterator>
#include <map>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <tuple>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

// --- generator.hpp ---
///////////////////////////////////////////////////////////////////////////////
// Copyright (c) Lewis Baker
// Licenced under MIT license. See LICENSE.txt for details.
///////////////////////////////////////////////////////////////////////////////
#ifndef CPPCORO_GENERATOR_HPP_INCLUDED
#define CPPCORO_GENERATOR_HPP_INCLUDED


namespace cppcoro
{
template <typename T>
class generator;

namespace detail
{
template <typename T>
class generator_promise
{
public:
    using value_type = std::remove_reference_t<T>;
    using reference_type = std::conditional_t<std::is_reference_v<T>, T, T&>;
    using pointer_type = value_type*;

    generator_promise() = default;

    generator<T> get_return_object() noexcept;

    constexpr std::suspend_always initial_suspend() const noexcept
    {
        return { };
    }
    constexpr std::suspend_always final_suspend() const noexcept
    {
        return { };
    }

    template <typename U = T, std::enable_if_t<!std::is_rvalue_reference<U>::value, int> = 0>
    std::suspend_always yield_value(std::remove_reference_t<T>& value) noexcept
    {
        m_value = std::addressof(value);
        return { };
    }

    std::suspend_always yield_value(std::remove_reference_t<T>&& value) noexcept
    {
        m_value = std::addressof(value);
        return { };
    }

    void unhandled_exception()
    {
        m_exception = std::current_exception();
    }

    void return_void() { }

    reference_type value() const noexcept
    {
        return static_cast<reference_type>(*m_value);
    }

    // Don't allow any use of 'co_await' inside the generator coroutine.
    template <typename U>
    std::suspend_never await_transform(U&& value) = delete;

    void rethrow_if_exception()
    {
        if (m_exception)
        {
            std::rethrow_exception(m_exception);
        }
    }

private:
    pointer_type m_value;
    std::exception_ptr m_exception;
};

struct generator_sentinel
{ };

template <typename T>
class generator_iterator
{
    using coroutine_handle = std::coroutine_handle<generator_promise<T>>;

public:
    using iterator_category = std::input_iterator_tag;
    // What type should we use for counting elements of a potentially infinite sequence?
    using difference_type = std::ptrdiff_t;
    using value_type = typename generator_promise<T>::value_type;
    using reference = typename generator_promise<T>::reference_type;
    using pointer = typename generator_promise<T>::pointer_type;

    // Iterator needs to be default-constructible to satisfy the Range concept.
    generator_iterator() noexcept
        : m_coroutine(nullptr)
    { }

    explicit generator_iterator(coroutine_handle coroutine) noexcept
        : m_coroutine(coroutine)
    { }

    friend bool operator==(const generator_iterator& it, generator_sentinel) noexcept
    {
        return !it.m_coroutine || it.m_coroutine.done();
    }

    friend bool operator!=(const generator_iterator& it, generator_sentinel s) noexcept
    {
        return !(it == s);
    }

    friend bool operator==(generator_sentinel s, const generator_iterator& it) noexcept
    {
        return (it == s);
    }

    friend bool operator!=(generator_sentinel s, const generator_iterator& it) noexcept
    {
        return it != s;
    }

    generator_iterator& operator++()
    {
        m_coroutine.resume();
        if (m_coroutine.done())
        {
            m_coroutine.promise().rethrow_if_exception();
        }

        return *this;
    }

    // Need to provide post-increment operator to implement the 'Range' concept.
    void operator++(int)
    {
        (void)operator++();
    }

    reference operator*() const noexcept
    {
        return m_coroutine.promise().value();
    }

    pointer operator->() const noexcept
    {
        return std::addressof(operator*());
    }

private:
    coroutine_handle m_coroutine;
};
}

template <typename T>
class [[nodiscard]] generator
{
public:
    using promise_type = detail::generator_promise<T>;
    using iterator = detail::generator_iterator<T>;

    generator() noexcept
        : m_coroutine(nullptr)
    { }

    generator(generator&& other) noexcept
        : m_coroutine(other.m_coroutine)
    {
        other.m_coroutine = nullptr;
    }

    generator(const generator& other) = delete;

    ~generator()
    {
        if (m_coroutine)
        {
            m_coroutine.destroy();
        }
    }

    generator& operator=(generator other) noexcept
    {
        swap(other);
        return *this;
    }

    iterator begin()
    {
        if (m_coroutine)
        {
            m_coroutine.resume();
            if (m_coroutine.done())
            {
                m_coroutine.promise().rethrow_if_exception();
            }
        }

        return iterator { m_coroutine };
    }

    detail::generator_sentinel end() noexcept
    {
        return detail::generator_sentinel { };
    }

    void swap(generator& other) noexcept
    {
        std::swap(m_coroutine, other.m_coroutine);
    }

private:
    friend class detail::generator_promise<T>;

    explicit generator(std::coroutine_handle<promise_type> coroutine) noexcept
        : m_coroutine(coroutine)
    { }

    std::coroutine_handle<promise_type> m_coroutine;
};

template <typename T>
void swap(generator<T>& a, generator<T>& b)
{
    a.swap(b);
}

namespace detail
{
template <typename T>
generator<T> generator_promise<T>::get_return_object() noexcept
{
    using coroutine_handle = std::coroutine_handle<generator_promise<T>>;
    return generator<T> { coroutine_handle::from_promise(*this) };
}
}

template <typename FUNC, typename T>
generator<std::invoke_result_t<FUNC&, typename generator<T>::iterator::reference>> fmap(FUNC func, generator<T> source)
{
    for (auto&& value : source)
    {
        co_yield std::invoke(func, static_cast<decltype(value)>(value));
    }
}
}

#endif

// --- type_cast_fwd.hpp ---

namespace expp
{
template <typename T>
struct type_cast;
}

// --- atom.hpp ---


namespace expp
{
struct atom
{
private:
    atom(const char* name, std::size_t len)
        : name(name, len)
    { }

    explicit atom(std::string name)
        : name(std::move(name))
    { }

    friend atom operator""_atom(const char* s, std::size_t len);

    friend struct type_cast<atom>;

public:
    bool operator==(const std::string_view sv) const
    {
        return this->name == sv;
    }

    bool operator!=(const std::string_view sv) const
    {
        return this->name != sv;
    }

    bool operator==(const atom& other) const
    {
        return this->name == other.name;
    }

    bool operator!=(const atom& other) const
    {
        return this->name != other.name;
    }

    std::string name;
};


inline atom operator""_atom(const char* s, std::size_t len)
{
    return atom { s, len };
}
}

// --- binary.hpp ---


namespace expp
{
class binary : public ErlNifBinary
{
private:
    ERL_NIF_TERM _term = 0;

    friend struct type_cast<binary>;

    binary& operator=(const binary&) = default;

public:
    binary()
    {
        this->size = 0;
        this->data = nullptr;
    }

    explicit binary(size_t size)
    {
        enif_alloc_binary(size, this);
    }

    template <size_t N>
    explicit binary(const char (&str)[N])
    {
        enif_alloc_binary(N - 1, this);
        std::copy_n(str, N - 1, this->data);
    }

    binary(binary&& other)
    {
        // No old data to release in a freshly constructed object
        static_cast<ErlNifBinary&>(*this) = static_cast<const ErlNifBinary&>(other);
        _term = other._term;

        other.data = nullptr;
        other.size = 0;
        other._term = 0;
    }

    binary(const binary& other) = delete;

    ~binary()
    {
        if (!this->_term && this->data)
        {
            enif_release_binary(this);
            this->size = 0;
            this->data = nullptr;
        }
    }

    template <typename T>
        requires((std::is_integral_v<T> && sizeof(T) == 1) || std::is_same_v<T, std::byte>)
    static binary from_bytes(const T* data, size_t size)
    {
        binary b { size };
        std::copy_n(data, size, b.data);
        return b;
    }

    binary& operator=(binary&& other)
    {
        if (this != &other)
        {
            // Release our current binary data if we own it
            if (!_term && data)
                enif_release_binary(this);

            // Transfer all fields from other
            static_cast<ErlNifBinary&>(*this) = static_cast<const ErlNifBinary&>(other);
            _term = other._term;

            other.data = nullptr;
            other.size = 0;
            other._term = 0;
        }
        return *this;
    }
};


inline binary operator""_binary(const char* s, std::size_t len)
{
    binary binary_info;
    enif_alloc_binary(len, &binary_info);
    std::copy_n(s, len, binary_info.data);
    return binary_info;
}
}

// --- resource.hpp ---


namespace expp
{
template <typename T, typename... Args>
inline constexpr bool is_brace_constructible_v = requires { T { std::declval<Args>()... }; };


template <typename T>
    requires std::destructible<T>
class resource
{
    ErlNifEnv* env;
    ERL_NIF_TERM term;
    void* objp;
    bool owns_;

    friend struct type_cast<resource<T>>;

    resource(ErlNifEnv* env, ERL_NIF_TERM term)
        : env(env)
        , term(term)
        , objp(nullptr)
        , owns_(false)
    { }

    resource(T* objp)
        : env(nullptr)
        , term(0)
        , objp(objp)
        , owns_(true)
    { }

public:
    typedef T type;

    resource(const resource<T>&) = delete;

    resource(resource<T>&& other)
        : env(other.env)
        , term(other.term)
        , objp(other.objp)
        , owns_(other.owns_)
    {
        other.objp = nullptr;
        other.owns_ = false;
    }

    ~resource()
    {
        if (owns_ && objp)
            enif_release_resource(objp);
    }

    template <typename U = T>
    U& get()
    {
        if (!enif_get_resource(env, term, resource<T>::resource_type, &this->objp))
            throw std::invalid_argument("invalid resource");
        return *reinterpret_cast<U*>(this->objp);
    }

    template <typename... Args>
        requires(is_brace_constructible_v<T, Args...>)
    static resource<T> alloc(Args&&... args)
    {
        void* buf = enif_alloc_resource(resource<T>::resource_type, sizeof(T));
        return resource<T> { new (buf) T { std::forward<Args>(args)... } };
    }

    static void init(ErlNifEnv* env, const char* name)
    {
        resource<T>::resource_type
            = enif_open_resource_type(env, nullptr, name, resource<T>::destructor, ERL_NIF_RT_CREATE, nullptr);
    }

    static void destructor(ErlNifEnv*, void* objp)
    {
        reinterpret_cast<T*>(objp)->~T();
    }

    static ErlNifResourceType* resource_type;
};


template <typename T>
    requires std::destructible<T>
ErlNifResourceType* resource<T>::resource_type = nullptr;
}

// --- casts.hpp ---


namespace expp
{
using namespace std::literals::string_view_literals;


template <typename T>
concept type_castable = requires(T t) {
    { type_cast<T>::to_term(nullptr, t) } -> std::same_as<ERL_NIF_TERM>;
    { type_cast<T>::from_term(nullptr, static_cast<ERL_NIF_TERM>(0)) } -> std::convertible_to<T>;
};


struct term
{
    ERL_NIF_TERM value;

    operator ERL_NIF_TERM() const
    {
        return value;
    }
};


template <>
struct type_cast<term>
{
    static term from_term(ErlNifEnv*, ERL_NIF_TERM t)
    {
        return term { t };
    }

    static ERL_NIF_TERM to_term(ErlNifEnv*, term t)
    {
        return t.value;
    }
};


template <std::integral T>
struct type_cast<T>
{
    static T from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        if constexpr (std::is_signed_v<T>)
        {
            if constexpr (sizeof(T) < 8)
            {
                int i;
                if (!enif_get_int(env, term, &i))
                    throw std::invalid_argument("invalid int");
                return static_cast<T>(i);
            }
            else
            {
                ErlNifSInt64 i;
                if (!enif_get_int64(env, term, &i))
                    throw std::invalid_argument("invalid int64");
                return static_cast<T>(i);
            }
        }
        else
        {
            if constexpr (sizeof(T) < 8)
            {
                unsigned int i;
                if (!enif_get_uint(env, term, &i))
                    throw std::invalid_argument("invalid uint");
                return static_cast<T>(i);
            }
            else
            {
                ErlNifUInt64 i;
                if (!enif_get_uint64(env, term, &i))
                    throw std::invalid_argument("invalid uint64");
                return static_cast<T>(i);
            }
        }
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, T i) noexcept
    {
        if constexpr (std::is_signed_v<T>)
        {
            if constexpr (sizeof(T) < 8)
                return enif_make_int(env, i);
            else
                return enif_make_int64(env, static_cast<ErlNifSInt64>(i));
        }
        else
        {
            if constexpr (sizeof(T) < 8)
                return enif_make_uint(env, i);
            else
                return enif_make_uint64(env, static_cast<ErlNifUInt64>(i));
        }
    }
};


template <std::floating_point T>
struct type_cast<T>
{
    static T from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        double d;
        if (!enif_get_double(env, term, &d))
            throw std::invalid_argument("invalid double");
        return static_cast<T>(d);
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, T d) noexcept
    {
        return enif_make_double(env, static_cast<double>(d));
    }
};


// Note: from_term always copies from the binary data into a new std::string.
// For read-only access without copying, prefer std::string_view.
template <>
struct type_cast<std::string>
{
    static std::string from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        ErlNifBinary binary_info;
        if (!enif_inspect_binary(env, term, &binary_info))
            throw std::invalid_argument("invalid string");
        return std::string(reinterpret_cast<const char*>(binary_info.data), binary_info.size);
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, const std::string& s)
    {
        ErlNifBinary binary_info;
        enif_alloc_binary(s.size(), &binary_info);
        std::copy_n(s.data(), s.size(), binary_info.data);
        return enif_make_binary(env, &binary_info);
    }
};


template <>
struct type_cast<std::string_view>
{
    static std::string_view from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        ErlNifBinary binary_info;
        if (!enif_inspect_binary(env, term, &binary_info))
            throw std::invalid_argument("invalid string");
        return std::string_view(reinterpret_cast<const char*>(binary_info.data), binary_info.size);
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, const std::string_view s)
    {
        ErlNifBinary binary_info;
        enif_alloc_binary(s.size(), &binary_info);
        std::copy_n(s.data(), s.size(), binary_info.data);
        return enif_make_binary(env, &binary_info);
    }
};


template <>
struct type_cast<binary>
{
    static binary from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        binary b;
        if (!enif_inspect_binary(env, term, &b))
            throw std::invalid_argument("invalid binary");
        b._term = term;
        return b;
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, const binary& b) noexcept
    {
        if (b._term)
            return b._term;

        auto b_ = const_cast<binary*>(&b);
        b_->_term = enif_make_binary(env, reinterpret_cast<ErlNifBinary*>(b_));

        return b_->_term;
    }
};


template <>
struct type_cast<atom>
{
    static atom from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        unsigned len;
        if (!enif_get_atom_length(env, term, &len, ERL_NIF_LATIN1))
            throw std::invalid_argument("invalid atom");
        std::string s(len, ' ');

        if (enif_get_atom(env, term, &s[0], len + 1, ERL_NIF_LATIN1) != int(len + 1))
            throw std::invalid_argument("invalid atom");

        return atom { s };
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, const atom& a) noexcept
    {
        return enif_make_atom_len(env, a.name.data(), a.name.length());
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, const std::string_view& s) noexcept
    {
        return enif_make_atom_len(env, s.data(), s.length());
    }
};


template <>
struct type_cast<bool>
{
    static bool from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        char buf[8];
        std::size_t bytes_read = enif_get_atom(env, term, buf, 8, ERL_NIF_LATIN1);
        if (bytes_read == 0)
            throw std::invalid_argument("not boolean");

        std::string_view atom_str(buf, bytes_read - 1);
        if (atom_str == "true"sv)
            return true;
        else if (atom_str == "false"sv)
            return false;
        else
            throw std::invalid_argument("not boolean");
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, bool b) noexcept
    {
        // enif_make_atom is internally interned by the VM, so calling it each
        // time is cheap and avoids caching ERL_NIF_TERMs across environments.
        if (b)
            return enif_make_atom(env, "true");
        else
            return enif_make_atom(env, "false");
    }
};


template <typename X, typename Y>
struct type_cast<std::pair<X, Y>>
{
    constexpr static std::pair<X, Y> from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        const ERL_NIF_TERM* tup_array = nullptr;
        int arity;
        if (!enif_get_tuple(env, term, &arity, &tup_array))
            throw std::invalid_argument("invalid pair");
        if (arity != 2)
            throw std::invalid_argument("invalid pair");
        return std::pair<X, Y>(type_cast<X>::from_term(env, tup_array[0]), type_cast<Y>::from_term(env, tup_array[1]));
    }

    constexpr static ERL_NIF_TERM to_term(ErlNifEnv* env, const std::pair<X, Y>& item) noexcept
    {
        return enif_make_tuple2(env, type_cast<X>::to_term(env, item.first), type_cast<Y>::to_term(env, item.second));
    }
};


template <typename... Args>
struct type_cast<std::tuple<Args...>>
{
private:
    typedef std::tuple<Args...> tuple_type;

    template <std::size_t... I>
    constexpr static tuple_type from_term_impl(ErlNifEnv* env, const ERL_NIF_TERM* tup_array, std::index_sequence<I...>)
    {
        return tuple_type(type_cast<std::decay_t<Args>>::from_term(env, tup_array[I])...);
    }

    template <std::size_t... I>
    constexpr static ERL_NIF_TERM
    to_term_impl(ErlNifEnv* env, const tuple_type& items, std::index_sequence<I...>) noexcept
    {
        return enif_make_tuple(
            env, std::tuple_size_v<tuple_type>, type_cast<std::decay_t<Args>>::to_term(env, std::get<I>(items))...);
    }

public:
    static tuple_type from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        const ERL_NIF_TERM* tup_array;
        int arity;
        if (!enif_get_tuple(env, term, &arity, &tup_array))
            throw std::invalid_argument("invalid tuple");
        if (arity != static_cast<int>(sizeof...(Args)))
            throw std::invalid_argument("invalid tuple arity");
        return from_term_impl(env, tup_array, std::index_sequence_for<Args...> { });
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, const tuple_type& items) noexcept
    {
        return to_term_impl(env, items, std::index_sequence_for<Args...> { });
    }
};


template <typename... Args>
struct type_cast<std::variant<Args...>>
{
private:
    typedef std::variant<Args...> variant_type;

    template <int I, typename T, typename... Rest>
    constexpr static variant_type from_term_impl(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        try
        {
            return variant_type(std::in_place_index<I>, type_cast<T>::from_term(env, term));
        }
        catch (const std::invalid_argument&)
        {
            if constexpr (sizeof...(Rest) == 0)
                throw std::invalid_argument("invalid argument");
            else
                return type_cast<variant_type>::from_term_impl<I + 1, Rest...>(env, term);
        }
    }

public:
    constexpr static variant_type from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        return type_cast<std::variant<Args...>>::from_term_impl<0, Args...>(env, term);
    }

    constexpr static ERL_NIF_TERM to_term(ErlNifEnv* env, const variant_type& item) noexcept
    {
        return std::visit(
            [env, &item](auto&& arg) {
                using T = std::decay_t<decltype(arg)>;
                return type_cast<T>::to_term(env, std::get<T>(item));
            },
            item);
    }
};


template <typename T, typename E>
struct type_cast<std::expected<T, E>>
{
private:
    typedef std::expected<T, E> expected_type;

public:
    static ERL_NIF_TERM to_term(ErlNifEnv* env, const expected_type& result) noexcept
    {
        if (result.has_value())
            return enif_make_tuple2(env, enif_make_atom(env, "ok"), type_cast<T>::to_term(env, *result));
        else
            return enif_make_tuple2(env, enif_make_atom(env, "error"), type_cast<E>::to_term(env, result.error()));
    };
};


template <typename T>
struct type_cast<std::optional<T>>
{
    static std::optional<T> from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        static_assert(!std::is_same_v<T, atom>, "std::optional cannot wrap an atom");

        if (enif_is_atom(env, term))
        {
            char buf[8];
            if (enif_get_atom(env, term, buf, 8, ERL_NIF_LATIN1) != 4)
                throw std::invalid_argument("not nil");
            if (std::string_view(buf, 3) != "nil")
                throw std::invalid_argument("not nil");
            return std::nullopt;
        }
        else
        {
            return type_cast<T>::from_term(env, term);
        }
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, const std::optional<T>& item)
    {
        if (item)
            return type_cast<T>::to_term(env, *item);
        else
            return enif_make_atom(env, "nil");
    }
};


template <typename T>
struct type_cast<resource<T>>
{
    static resource<T> from_term(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        return resource<T> { env, term };
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, const resource<T>& res)
    {
        // Just create the term — the resource<T> destructor will call
        // enif_release_resource when the object goes out of scope,
        // leaving the term as the sole owner of the NIF resource.
        return enif_make_resource(env, res.objp);
    }
};
}

// --- ext_types.hpp ---


namespace expp
{
struct erl_error_base : std::exception
{
    virtual ERL_NIF_TERM get_term(ErlNifEnv* env) const = 0;
};


// this exception is automatically converted to {:error, <error_value>}
template <std::copy_constructible T>
struct erl_error : erl_error_base
{
    T error_value;

    constexpr explicit erl_error(const T& error_value)
        : error_value(error_value)
    { }

    ERL_NIF_TERM get_term(ErlNifEnv* env) const
    {
        using error_type = std::tuple<atom, std::decay_t<T>>;
        return type_cast<error_type>::to_term(env, error_type("error"_atom, error_value));
    }
};


namespace exceptions
{
inline ERL_NIF_TERM raise_error_with_message(ErlNifEnv* env, const char* module_name, std::string_view message)
{
    ERL_NIF_TERM keys[3]
        = { enif_make_atom(env, "__struct__"), enif_make_atom(env, "__exception__"), enif_make_atom(env, "message") };
    ERL_NIF_TERM values[3] = { enif_make_atom(env, module_name),
                               enif_make_atom(env, "true"),
                               type_cast<std::string_view>::to_term(env, message) };

    ERL_NIF_TERM map;
    if (!enif_make_map_from_arrays(env, keys, values, 3, &map))
    {
        return enif_raise_exception(env, type_cast<std::string_view>::to_term(env, message));
    }

    return enif_raise_exception(env, map);
}

inline ERL_NIF_TERM raise_argument_error(ErlNifEnv* env, std::string_view message)
{
    return raise_error_with_message(env, "Elixir.ArgumentError", message);
}

inline ERL_NIF_TERM raise_runtime_error(ErlNifEnv* env, std::string_view message)
{
    return raise_error_with_message(env, "Elixir.RuntimeError", message);
}
}
}

// --- stl.hpp ---


namespace expp
{
template <typename T>
concept InnerType = (std::is_move_constructible_v<T> || std::is_copy_constructible_v<T>)
    && (type_castable<T> || std::is_same_v<T, std::byte>);


template <class F>
class scope_exit
{
    F f;

public:
    explicit scope_exit(F&& f)
        : f(std::forward<F>(f))
    { }

    scope_exit(scope_exit&& other) = delete;

    ~scope_exit()
    {
        f();
    }

    scope_exit(const scope_exit&) = delete;
    scope_exit& operator=(const scope_exit&) = delete;
};

template <class F>
scope_exit(F) -> scope_exit<F>;

template <InnerType T>
struct type_cast<std::vector<T>>
{
private:
    typedef std::decay_t<T> item_type;

public:
    constexpr static std::vector<T> from_term(ErlNifEnv* env, const ERL_NIF_TERM term)
    {
        if constexpr ((std::is_integral_v<T> && sizeof(T) == 1) || std::is_same_v<T, std::byte>)
        {
            ErlNifBinary binary_info;
            if (!enif_inspect_binary(env, term, &binary_info))
                throw std::invalid_argument("invalid string");
            auto begin = reinterpret_cast<const T*>(binary_info.data);
            auto end = begin + binary_info.size;
            return std::vector<T>(begin, end);
        }
        else
        {
            unsigned len = 0;
            if (!enif_get_list_length(env, term, &len))
                throw std::invalid_argument("invalid vector");

            std::vector<T> items;
            items.reserve(len);
            ERL_NIF_TERM list_term = term;
            for (unsigned i = 0; i < len; i++)
            {
                ERL_NIF_TERM head, tail;
                enif_get_list_cell(env, list_term, &head, &tail);
                items.push_back(type_cast<item_type>::from_term(env, head));
                list_term = tail;
            }

            return items;
        }
    }

    static ERL_NIF_TERM to_term(ErlNifEnv* env, const std::vector<T>& items) noexcept
    {
        if constexpr ((std::is_integral_v<T> && sizeof(T) == 1) || std::is_same_v<T, std::byte>)
        {
            ErlNifBinary binary_info;
            enif_alloc_binary(items.size(), &binary_info);
            std::copy_n(reinterpret_cast<const unsigned char*>(items.data()), items.size(), binary_info.data);
            return enif_make_binary(env, &binary_info);
        }
        else
        {
            ERL_NIF_TERM list = enif_make_list(env, 0);
            for (auto it = items.rbegin(); it != items.rend(); ++it)
                list = enif_make_list_cell(env, type_cast<item_type>::to_term(env, *it), list);
            return list;
        }
    }
};


template <InnerType K, InnerType V>
struct type_cast<std::unordered_map<K, V>>
{
private:
    typedef std::decay_t<K> key_type;
    typedef std::decay_t<V> value_type;
    typedef std::unordered_map<key_type, value_type> map_type;

public:
    constexpr static map_type from_term(ErlNifEnv* env, const ERL_NIF_TERM term)
    {
        map_type _map;
        std::size_t size;
        if (!enif_get_map_size(env, term, &size))
            throw std::invalid_argument("invalid map");
        _map.reserve(size);

        ErlNifMapIterator iter;
        if (!enif_map_iterator_create(env, term, &iter, ERL_NIF_MAP_ITERATOR_FIRST))
            throw std::invalid_argument("invalid map");

        auto guard = scope_exit([env, &iter]() { enif_map_iterator_destroy(env, &iter); });

        ERL_NIF_TERM key, value;
        while (enif_map_iterator_get_pair(env, &iter, &key, &value))
        {
            _map.emplace(type_cast<key_type>::from_term(env, key), type_cast<value_type>::from_term(env, value));
            enif_map_iterator_next(env, &iter);
        }

        return _map;
    }

    constexpr static ERL_NIF_TERM to_term(ErlNifEnv* env, const map_type& _map) noexcept
    {
        std::vector<ERL_NIF_TERM> keys;
        std::vector<ERL_NIF_TERM> values;
        keys.reserve(_map.size());
        values.reserve(_map.size());

        for (const auto& item : _map)
        {
            keys.push_back(type_cast<key_type>::to_term(env, item.first));
            values.push_back(type_cast<value_type>::to_term(env, item.second));
        }

        ERL_NIF_TERM map_term;
        enif_make_map_from_arrays(env, keys.data(), values.data(), keys.size(), &map_term);
        return map_term;
    }
};


template <InnerType K, InnerType V>
struct type_cast<std::map<K, V>>
{
private:
    typedef std::decay_t<K> key_type;
    typedef std::decay_t<V> value_type;
    typedef std::map<key_type, value_type> map_type;

public:
    constexpr static map_type from_term(ErlNifEnv* env, const ERL_NIF_TERM term)
    {
        map_type _map;
        std::size_t size;
        if (!enif_get_map_size(env, term, &size))
            throw std::invalid_argument("invalid map");

        ErlNifMapIterator iter;
        if (!enif_map_iterator_create(env, term, &iter, ERL_NIF_MAP_ITERATOR_FIRST))
            throw std::invalid_argument("invalid map");

        auto guard = scope_exit([env, &iter]() { enif_map_iterator_destroy(env, &iter); });

        ERL_NIF_TERM key, value;
        while (enif_map_iterator_get_pair(env, &iter, &key, &value))
        {
            _map.emplace(type_cast<key_type>::from_term(env, key), type_cast<value_type>::from_term(env, value));
            enif_map_iterator_next(env, &iter);
        }

        return _map;
    }

    constexpr static ERL_NIF_TERM to_term(ErlNifEnv* env, const map_type& _map) noexcept
    {
        std::vector<ERL_NIF_TERM> keys;
        std::vector<ERL_NIF_TERM> values;
        keys.reserve(_map.size());
        values.reserve(_map.size());

        for (const auto& item : _map)
        {
            keys.push_back(type_cast<key_type>::to_term(env, item.first));
            values.push_back(type_cast<value_type>::to_term(env, item.second));
        }

        ERL_NIF_TERM map_term;
        enif_make_map_from_arrays(env, keys.data(), values.data(), keys.size(), &map_term);
        return map_term;
    }
};
}

// --- yielding.hpp ---


namespace expp
{
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


// Type-erased base for yielding coroutine resources, enabling virtual dispatch
// instead of type-punning through resource<yielding<int>>.
struct yielding_resource_base
{
    virtual ~yielding_resource_base() = default;
    virtual ERL_NIF_TERM step(ErlNifEnv* env) = 0;
};


template <typename GeneratorType>
struct yielding_resource_impl : yielding_resource_base
{
    GeneratorType coro;

    explicit yielding_resource_impl(GeneratorType&& c)
        : coro(std::move(c))
    { }

    ERL_NIF_TERM step(ErlNifEnv* env) override
    {
        try
        {
            if (const auto& out = *std::begin(coro); out)
            {
                return type_cast<std::decay_t<decltype(*out)>>::to_term(env, *out);
            }
            else
                return 0;  // indicates that it needs to be scheduled for another step
        }
        catch (const erl_error_base& e)
        {
            return e.get_term(env);
        }
        catch (const std::exception& e)
        {
            return exceptions::raise_runtime_error(env, e.what());
        }
    }
};


using yielding_resource_t = resource<std::unique_ptr<yielding_resource_base>>;
}

// --- expp.hpp ---


namespace expp
{
template <typename T>
struct function_traits;

template <typename R, typename... Args, bool IsNoexcept>
struct function_traits<R (*)(Args...) noexcept(IsNoexcept)>
{
    using func_type = R(Args...) noexcept(IsNoexcept);
    using return_type = R;
    static constexpr size_t nargs = sizeof...(Args);

    template <func_type fn, std::size_t... I>
    constexpr static R apply_impl(ErlNifEnv* env, const ERL_NIF_TERM argv[], std::index_sequence<I...>)
    {
        return fn(type_cast<std::decay_t<Args>>::from_term(env, argv[I])...);
    }

    template <func_type fn>
    constexpr static R apply(ErlNifEnv* env, const ERL_NIF_TERM argv[])
    {
        return apply_impl<fn>(env, argv, std::make_index_sequence<nargs> { });
    }

    constexpr static bool any_args_by_reference()
    {
        return (... || std::is_reference_v<Args>);
    }

    template <typename U>
    constexpr static bool any_args_has_type()
    {
        return (... || std::is_same_v<Args, U>);
    }
};


inline ERL_NIF_TERM coroutine_step(ErlNifEnv* env, int, const ERL_NIF_TERM argv[])
{
    auto coroutine_resource = type_cast<yielding_resource_t>::from_term(env, argv[0]);
    auto& impl_ptr = coroutine_resource.get();

    if (ERL_NIF_TERM step_result = impl_ptr->step(env); step_result)
        return step_result;
    else
        return enif_schedule_nif(env, "coroutine_step", 0, coroutine_step, 1, argv);
}


template <auto fn>
constexpr ERL_NIF_TERM wrapper(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    using func_traits = function_traits<decltype(fn)>;

    if (argc != func_traits::nargs)
        return enif_make_badarg(env);

    try
    {
        using return_type = typename func_traits::return_type;

        if constexpr (std::is_void_v<return_type>)
        {
            func_traits::template apply<fn>(env, argv);
            return enif_make_atom(env, "ok");
        }
        else if constexpr (is_yielding_v<return_type>)
        {
            auto ret = func_traits::template apply<fn>(env, argv);

            // Do some type-checking to make sure we don't run into trouble:
            // Because generator functions can be resumed, they cannot take
            // 1. arguments by reference (the original stack is gone when it's resumed)
            // 2. arguments of type binary (the data pointer might be invalidated when it's resumed)
            static_assert(
                !func_traits::any_args_by_reference(), "generator functions cannot have pass-by-reference arguments");
            static_assert(
                !func_traits::template any_args_has_type<binary>(),
                "generator functions cannot have arguments of type binary");

            // Wrap the generator in a type-erased impl
            auto impl = std::make_unique<yielding_resource_impl<return_type>>(std::move(ret));

            // Try to step the generator one time
            if (auto step_output = impl->step(env); step_output)
                return step_output;
            else
            {
                // Allocate a resource for the generator and schedule it for later execution
                auto res = yielding_resource_t::alloc(std::move(impl));
                ERL_NIF_TERM resource_term = type_cast<yielding_resource_t>::to_term(env, res);
                ERL_NIF_TERM out[] = { resource_term };
                return enif_schedule_nif(env, "coroutine_step", 0, coroutine_step, 1, out);
            }
        }
        else
        {
            auto ret = func_traits::template apply<fn>(env, argv);
            return type_cast<std::decay_t<decltype(ret)>>::to_term(env, std::move(ret));
        }
    }
    catch (const std::invalid_argument& e)
    {
        return exceptions::raise_argument_error(env, e.what());
    }
    catch (const erl_error_base& e)
    {
        return e.get_term(env);
    }
    catch (const std::exception& e)
    {
        return exceptions::raise_runtime_error(env, e.what());
    }
    catch (...)
    {
        return exceptions::raise_runtime_error(env, "unknown exception");
    }
}


enum class DirtyFlags
{
    NotDirty = 0,
    DirtyCpu = ERL_NIF_DIRTY_JOB_CPU_BOUND,
    DirtyIO = ERL_NIF_DIRTY_JOB_IO_BOUND,
};


template <auto fn, DirtyFlags dirty_flag>
consteval ErlNifFunc def_impl(const char* name)
{
    ErlNifFunc entry = {
        name,
        function_traits<decltype(fn)>::nargs,
        wrapper<fn>,
        static_cast<int>(dirty_flag),
    };
    return entry;
}
}


/*
macro overloading trick:
https://stackoverflow.com/questions/11761703/overloading-macro-on-number-of-arguments
We want to be able to write:

    def(add, "add)
    def(add)  // defaults to using the same name as the function
*/
#define DEF2(fn, dirty_flag) expp::def_impl<fn, dirty_flag>(#fn)
#define DEF3(fn, name, dirty_flag) expp::def_impl<fn, dirty_flag>(name)
#define GET_MACRO(_1, _2, _3, NAME, ...) NAME
#define def(...) GET_MACRO(__VA_ARGS__, DEF3, DEF2, UNUSED)(__VA_ARGS__)


#define MODULE(NAME, LOAD, UPGRADE, UNLOAD, ...)                                                                       \
    ErlNifFunc _nif_funcs[] = { __VA_ARGS__ };                                                                         \
    ERL_NIF_INIT(NAME, _nif_funcs, LOAD, nullptr, UPGRADE, UNLOAD)
