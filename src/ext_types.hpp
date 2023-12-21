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


template <std::move_constructible OkType>
struct Ok
{
    OkType value;

    constexpr explicit Ok(OkType&& value)
        : value(std::move(value))
    { }
};


template <std::move_constructible ErrorType>
struct Error
{
    ErrorType value;

    constexpr explicit Error(ErrorType&& value)
        : value(std::move(value))
    { }
};


template <size_t N>
Error(const char (&)[N]) -> Error<std::string_view>;


template <std::move_constructible OkType, std::move_constructible ErrorType>
struct erl_result : std::variant<OkType, ErrorType>
{
    constexpr erl_result(Ok<OkType> ok_value)
        : std::variant<OkType, ErrorType>(std::in_place_index<0>, std::move(ok_value.value))
    { }

    template <std::constructible_from<ErrorType> U>
    constexpr erl_result(Error<U> error_value)
        : std::variant<OkType, ErrorType>(std::in_place_index<1>, std::move(error_value.value))
    { }

    constexpr bool ok() const
    {
        return this->index() == 0;
    }
};
