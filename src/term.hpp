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
    bool is_fun() const
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
