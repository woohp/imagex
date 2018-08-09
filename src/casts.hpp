#pragma once
#include <algorithm>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <tuple>
#include <variant>
#include <erl_nif.h>
#include "atom.hpp"


template<typename T>
struct type_cast;


class blob
{
private:
    ErlNifBinary binary_info;

    friend struct type_cast<blob>;

    blob()
    {}

public:
    explicit blob(unsigned size)
    {
        enif_alloc_binary(size, &this->binary_info);
    }

    unsigned char* data() const
    {
        return this->binary_info.data;
    }

    unsigned size() const
    {
        return this->binary_info.size;
    }
};


template<>
struct type_cast<int>
{
    static int load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        int i;
        if (!enif_get_int(env, term, &i))
            throw std::invalid_argument("invalid int");
        return i;
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, int i) noexcept
    {
        return enif_make_int(env, i);
    }
};


template<>
struct type_cast<uint32_t>
{
    static uint32_t load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        uint32_t i;
        if (!enif_get_uint(env, term, &i))
            throw std::invalid_argument("invalid uint");
        return i;
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, uint32_t i) noexcept
    {
        return enif_make_uint(env, i);
    }
};


template<>
struct type_cast<int64_t>
{
    static int64_t load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        int64_t i;
        if (!enif_get_int64(env, term, reinterpret_cast<ErlNifSInt64*>(&i)))
            throw std::invalid_argument("invalid int64");
        return i;
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, int64_t i) noexcept
    {
        return enif_make_int64(env, i);
    }
};


template<>
struct type_cast<uint64_t>
{
    static uint64_t load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        uint64_t i;
        if (!enif_get_uint64(env, term, reinterpret_cast<ErlNifUInt64*>(&i)))
            throw std::invalid_argument("invalid uint64");
        return i;
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, uint64_t i) noexcept
    {
        return enif_make_uint64(env, i);
    }
};


template<>
struct type_cast<double>
{
    static double load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        double d;
        if (!enif_get_double(env, term, &d))
            throw std::invalid_argument("invalid double");
        return d;
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, double d) noexcept
    {
        return enif_make_double(env, d);
    }
};


template<>
struct type_cast<std::string>
{
    static std::string load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        ErlNifBinary binary_info;
        enif_inspect_binary(env, term, &binary_info);
        return std::string(reinterpret_cast<const char*>(binary_info.data), binary_info.size);
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const std::string& s) noexcept
    {
        ErlNifBinary binary_info;
        enif_alloc_binary(s.size(), &binary_info);
        std::copy_n(s.data(), s.size(), binary_info.data);
        return enif_make_binary(env, &binary_info);
    }
};


template<>
struct type_cast<blob>
{
    static blob load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        blob b;
        enif_inspect_binary(env, term, &b.binary_info);
        return b;
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const blob& b) noexcept
    {
        return enif_make_binary(env, const_cast<ErlNifBinary*>(&b.binary_info));
    }
};


template<>
struct type_cast<atom>
{
    static atom load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        unsigned len;
        if (!enif_get_atom_length(env, term, &len, ERL_NIF_LATIN1))
            throw std::invalid_argument("invalid atom");
        std::string s(len, ' ');

        if (enif_get_atom(env, term, &s[0], len + 1, ERL_NIF_LATIN1) != int(len + 1))
            throw std::invalid_argument("invalid atom");

        return atom(s);
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const atom& a) noexcept
    {
        return enif_make_atom(env, a.name.c_str());
    }
};


template<typename X, typename Y>
struct type_cast<std::pair<X, Y>>
{
    static std::pair<X, Y> load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        const ERL_NIF_TERM* tup_array;
        int arity;
        if (!enif_get_tuple(env, term, &arity, &tup_array))
            throw std::invalid_argument("invalid pair");
        if (arity != 2)
            throw std::invalid_argument("invalid pair");
        return std::pair<X, Y>(type_cast<X>::load(env, tup_array[0]),
                          type_cast<Y>::load(env, tup_array[1]));
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const std::pair<X, Y>& item) noexcept
    {
        return enif_make_tuple2(
            env,
            type_cast<X>::handle(env, item.first),
            type_cast<Y>::handle(env, item.second)
        );
    }
};


template<typename ...Args>
struct type_cast<std::tuple<Args...>>
{
private:
    typedef std::tuple<Args...> tuple_type;

    template<std::size_t... I>
    static tuple_type load_impl(ErlNifEnv* env, const ERL_NIF_TERM* tup_array, std::index_sequence<I...>)
    {
        return tuple_type(type_cast<std::decay_t<Args>>::load(env, tup_array[I])...);
    }

    template<std::size_t... I>
    static ERL_NIF_TERM handle_impl(ErlNifEnv* env, const tuple_type& items, std::index_sequence<I...>) noexcept
    {
        return enif_make_tuple(
            env,
            std::tuple_size<tuple_type>::value,
            type_cast<std::decay_t<Args>>::handle(env, std::get<I>(items))...
        );
    }

public:
    static tuple_type load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        const ERL_NIF_TERM* tup_array;
        int arity;
        if (!enif_get_tuple(env, term, &arity, &tup_array))
            throw std::invalid_argument("invalid tuple");
        return load_impl(env, tup_array, std::index_sequence_for<Args...>{});
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const tuple_type& items) noexcept
    {
        return handle_impl(env, items, std::index_sequence_for<Args...>{});
    }
};


template<typename ...Args>
struct type_cast<std::variant<Args...>>
{
private:
    typedef std::variant<Args...> variant_type;

public:
    // static variant_type load(ErlNifEnv* env, ERL_NIF_TERM term)
    // {
    // }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const variant_type& item) noexcept
    {
        return std::visit([env, &item](auto&& arg) {
            using T = std::decay_t<decltype(arg)>;
            return type_cast<T>::handle(env, std::get<T>(item));
        }, item);
    }
};
