#pragma once
#include "atom.hpp"
#include "binary.hpp"
#include "ext_types.hpp"
#include "resource.hpp"
#include <algorithm>
#include <cstdint>
#include <erl_nif.h>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <tuple>
#include <variant>

using namespace std::literals::string_view_literals;


template <typename T>
struct type_cast;


template <>
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


template <>
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


template <>
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


template <>
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


template <>
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


template <>
struct type_cast<std::string>
{
    static std::string load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        ErlNifBinary binary_info;
        if (!enif_inspect_binary(env, term, &binary_info))
            throw std::invalid_argument("invalid string");
        return std::string(reinterpret_cast<const char*>(binary_info.data), binary_info.size);
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const std::string& s)
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
    static binary load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        binary b;
        if (!enif_inspect_binary(env, term, &b))
            throw std::invalid_argument("invalid binary");
        b._term = term;
        return b;
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const binary& b) noexcept
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
    static atom load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        unsigned len;
        if (!enif_get_atom_length(env, term, &len, ERL_NIF_LATIN1))
            throw std::invalid_argument("invalid atom");
        std::string s(len, ' ');

        if (enif_get_atom(env, term, &s[0], len + 1, ERL_NIF_LATIN1) != int(len + 1))
            throw std::invalid_argument("invalid atom");

        return atom { s };
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const atom& a) noexcept
    {
        return enif_make_atom_len(env, a.name.data(), a.name.length());
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const std::string_view& s) noexcept
    {
        return enif_make_atom_len(env, s.data(), s.length());
    }
};


template <>
struct type_cast<bool>
{
    static bool load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        char buf[8];
        int bytes_read = enif_get_atom(env, term, buf, 8, ERL_NIF_LATIN1);
        if (bytes_read == 5 && std::string_view(buf, 4) == "true")
            return true;
        else if (bytes_read == 6 && std::string_view(buf, 5) == "false")
            return false;
        else
            throw std::invalid_argument("not boolean");
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, bool b) noexcept
    {
        static ERL_NIF_TERM true_atom_term = type_cast<atom>::handle(env, "true"sv);
        static ERL_NIF_TERM false_atom_term = type_cast<atom>::handle(env, "false"sv);
        if (b)
            return true_atom_term;
        else
            return false_atom_term;
    }
};


template <typename X, typename Y>
struct type_cast<std::pair<X, Y>>
{
    constexpr static std::pair<X, Y> load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        const ERL_NIF_TERM* tup_array = nullptr;
        int arity;
        if (!enif_get_tuple(env, term, &arity, &tup_array))
            throw std::invalid_argument("invalid pair");
        if (arity != 2)
            throw std::invalid_argument("invalid pair");
        return std::pair<X, Y>(type_cast<X>::load(env, tup_array[0]), type_cast<Y>::load(env, tup_array[1]));
    }

    constexpr static ERL_NIF_TERM handle(ErlNifEnv* env, const std::pair<X, Y>& item) noexcept
    {
        return enif_make_tuple2(env, type_cast<X>::handle(env, item.first), type_cast<Y>::handle(env, item.second));
    }
};


template <typename... Args>
struct type_cast<std::tuple<Args...>>
{
private:
    typedef std::tuple<Args...> tuple_type;

    template <std::size_t... I>
    constexpr static tuple_type load_impl(ErlNifEnv* env, const ERL_NIF_TERM* tup_array, std::index_sequence<I...>)
    {
        return tuple_type(type_cast<std::decay_t<Args>>::load(env, tup_array[I])...);
    }

    template <std::size_t... I>
    constexpr static ERL_NIF_TERM
    handle_impl(ErlNifEnv* env, const tuple_type& items, std::index_sequence<I...>) noexcept
    {
        return enif_make_tuple(
            env, std::tuple_size_v<tuple_type>, type_cast<std::decay_t<Args>>::handle(env, std::get<I>(items))...);
    }

public:
    static tuple_type load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        const ERL_NIF_TERM* tup_array;
        int arity;
        if (!enif_get_tuple(env, term, &arity, &tup_array))
            throw std::invalid_argument("invalid tuple");
        return load_impl(env, tup_array, std::index_sequence_for<Args...> {});
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const tuple_type& items) noexcept
    {
        return handle_impl(env, items, std::index_sequence_for<Args...> {});
    }
};


template <typename... Args>
struct type_cast<std::variant<Args...>>
{
private:
    typedef std::variant<Args...> variant_type;

    template <int I, typename T, typename... Rest>
    constexpr static variant_type load_impl(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        try
        {
            return variant_type(std::in_place_index<I>, type_cast<T>::load(env, term));
        }
        catch (const std::invalid_argument&)
        {
            if constexpr (sizeof...(Rest) == 0)
                throw std::invalid_argument("invalid argument");
            else
                return type_cast<variant_type>::load_impl<I + 1, Rest...>(env, term);
        }
    }

public:
    constexpr static variant_type load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        return type_cast<std::variant<Args...>>::load_impl<0, Args...>(env, term);
    }

    constexpr static ERL_NIF_TERM handle(ErlNifEnv* env, const variant_type& item) noexcept
    {
        return std::visit(
            [env, &item](auto&& arg) {
                using T = std::decay_t<decltype(arg)>;
                return type_cast<T>::handle(env, std::get<T>(item));
            },
            item);
    }
};


template <typename OkType, typename ErrorType>
struct type_cast<erl_result<OkType, ErrorType>>
{
private:
    typedef erl_result<OkType, ErrorType> erl_result_type;
    typedef std::tuple<atom, OkType> ok_tuple_type;
    typedef std::tuple<atom, ErrorType> error_tuple_type;

public:
    static ERL_NIF_TERM handle(ErlNifEnv* env, const erl_result_type& result) noexcept
    {
        static ERL_NIF_TERM ok_atom_term = type_cast<atom>::handle(env, "ok"sv);
        static ERL_NIF_TERM error_atom_term = type_cast<atom>::handle(env, "error"sv);

        if (result.index() == 0)
            return enif_make_tuple2(env, ok_atom_term, type_cast<OkType>::handle(env, std::get<0>(result)));
        else
            return enif_make_tuple2(env, error_atom_term, type_cast<ErrorType>::handle(env, std::get<1>(result)));
    };
};


template <typename T>
struct type_cast<std::optional<T>>
{
    static std::optional<T> load(ErlNifEnv* env, ERL_NIF_TERM term)
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
            return type_cast<T>::load(env, term);
        }
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const std::optional<T>& item)
    {
        if (item)
            return type_cast<T>::handle(env, *item);
        else
        {
            static ERL_NIF_TERM nil_atom_term = type_cast<atom>::handle(env, "nil"sv);
            return nil_atom_term;
        }
    }
};


template <typename T>
struct type_cast<resource<T>>
{
    static resource<T> load(ErlNifEnv* env, ERL_NIF_TERM term)
    {
        return resource<T> { env, term };
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const resource<T>& res)
    {
        const auto document_term = enif_make_resource(env, res.objp);
        enif_release_resource(res.objp);
        return document_term;
    }
};
