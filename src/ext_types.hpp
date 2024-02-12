#pragma once
#include "atom.hpp"
#include <erl_nif.h>
#include <stdexcept>
#include <tuple>
#include <variant>


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
        return type_cast<error_type>::handle(env, error_type("error"_atom, error_value));
    }
};
