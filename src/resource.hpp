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
    typedef T type;

    resource(const resource<T>&) = delete;
    resource(resource<T>&&) = default;

    T& get()
    {
        if (!enif_get_resource(env, term, resource<T>::resource_type, &this->objp))
            throw std::invalid_argument("invalid resource");
        return *reinterpret_cast<T*>(this->objp);
    }

    template <typename... Args>
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
ErlNifResourceType* resource<T>::resource_type = nullptr;
