#pragma once
#include <erl_nif.h>


template <typename T>
class resource
{
    ErlNifEnv* env;
    ERL_NIF_TERM term;
    void* objp;

    friend struct type_cast<resource<T>>;

    resource(ErlNifEnv* env, ERL_NIF_TERM term)
        : env(env)
        , term(term)
        , objp(nullptr)
    { }

    resource(T* objp)
        : env(nullptr)
        , term(0)
        , objp(objp)
    { }

public:
    T& get()
    {
        if (!enif_get_resource(env, term, resource<T>::resource_type, &this->objp))
            throw std::invalid_argument("invalid resource");
        return *reinterpret_cast<T*>(this->objp);
    }

    static resource<T> alloc(const T& obj)
    {
        assert(resource<T>::resource_type);
        T* objp = reinterpret_cast<T*>(enif_alloc_resource(resource<T>::resource_type, sizeof(T)));
        *objp = obj;
        return resource<T> { objp };
    }

    static ErlNifResourceType* resource_type;
};


template <typename T>
ErlNifResourceType* resource<T>::resource_type = nullptr;
