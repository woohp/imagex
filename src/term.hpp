#pragma once
#include "casts.hpp"
#include <erl_nif.h>


struct term
{
    bool is_atom() const
    {
        return enif_is_atom(this->env, this->term);
    }

    bool is_binary() const
    {
        return enif_is_binary(this->env, this->term);
    }

    bool is_function() const
    {
        return enif_is_fun(this->env, this->term);
    }

    bool is_map() const
    {
        return enif_is_map(this->env, this->term);
    }

    bool is_number() const
    {
        return enif_is_number(this->env, this->term);
    }

    bool is_tuple() const
    {
        return enif_is_map(this->env, this->term);
    }

    atom get_atom() const
    {
        return type_cast<atom>::load(this->env, term);
    }

    ErlNifEnv* env;
    ERL_NIF_TERM term;
};


template <>
struct type_cast<term>
{
    static term load(ErlNifEnv* env, ERL_NIF_TERM _term)
    {
        return term { env, _term };
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, term _term)
    {
        return _term.term;
    }
};
