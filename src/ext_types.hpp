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


template <typename T>
struct erl_error : erl_error_base
{
    T error_value;

    explicit erl_error(const T& error_value)
        : error_value(error_value)
    { }

    ERL_NIF_TERM get_term(ErlNifEnv* env) const
    {
        using error_type = std::tuple<atom, std::decay_t<T>>;
        return type_cast<error_type>::handle(env, error_type("error"_atom, error_value));
    }
};


template <typename OkType>
struct Ok
{
    OkType value;

    explicit Ok(OkType value)
        : value(std::move(value))
    { }
};


template <typename ErrorType>
struct Error
{
    ErrorType value;

    explicit Error(ErrorType value)
        : value(std::move(value))
    { }
};


template <typename OkType, typename ErrorType>
struct erl_result : std::variant<OkType, ErrorType>
{
    erl_result(Ok<OkType> ok_value)
        : std::variant<OkType, ErrorType>(std::in_place_index<0>, std::move(ok_value.value))
    { }

    erl_result(Error<ErrorType> error_value)
        : std::variant<OkType, ErrorType>(std::in_place_index<1>, std::move(error_value.value))
    { }

    bool ok() const
    {
        return this->index() == 0;
    }
};
