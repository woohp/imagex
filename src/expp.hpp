#pragma once
#include "casts.hpp"
#include "ext_types.hpp"
#include <erl_nif.h>
#include <utility>


template <typename T>
struct function_traits;

template <typename R, typename... Args, bool IsNoexcept>
struct function_traits<R (*)(Args...) noexcept(IsNoexcept)>
{
    using func_type = R(Args...) noexcept(IsNoexcept);
    static constexpr size_t nargs = sizeof...(Args);

    template <std::size_t... I>
    static R apply_impl(func_type fn, ErlNifEnv* env, const ERL_NIF_TERM argv[], std::index_sequence<I...>) noexcept(IsNoexcept)
    {
        return fn(type_cast<std::decay_t<Args>>::load(env, argv[I])...);
    }

    static R apply(func_type fn, ErlNifEnv* env, const ERL_NIF_TERM argv[]) noexcept(IsNoexcept)
    {
        return apply_impl(fn, env, argv, std::make_index_sequence<nargs> {});
    }
};


template <typename Fn, Fn fn>
ERL_NIF_TERM wrapper(ErlNifEnv* env, int, const ERL_NIF_TERM argv[])
{
    using func_traits = function_traits<Fn>;
    try
    {
        auto ret = func_traits::apply(fn, env, argv);
        return type_cast<std::decay_t<decltype(ret)>>::handle(env, std::move(ret));
    }
    catch (const std::invalid_argument& e)
    {
        return enif_make_badarg(env);
    }
    catch (const erl_error_base& e)
    {
        return e.get_term(env);
    }
    catch (const std::exception& e)
    {
        auto reason = type_cast<std::string>::handle(env, e.what());
        return enif_raise_exception(env, reason);
    }
}


template <typename Fn, Fn fn>
ErlNifFunc constexpr def_impl(const char* name)
{
    ErlNifFunc entry = {
        name,
        function_traits<Fn>::nargs,
        wrapper<Fn, fn>,
        0,
    };
    return entry;
}


/*
macro overloading trick:
https://stackoverflow.com/questions/11761703/overloading-macro-on-number-of-arguments
We want to be able to write:

    def(add, "add)
    def(add)  // defaults to using the same name as the function
*/
#define DEF1(fn) def_impl<decltype(&fn), fn>(#fn)
#define DEF2(fn, name) def_impl<decltype(&fn), fn>(name)
#define GET_MACRO(_1,_2,NAME,...) NAME
#define def(...) GET_MACRO(__VA_ARGS__, DEF2, DEF1, UNUSED)(__VA_ARGS__)


#define MODULE(name, ...)                                                                                       \
    ErlNifFunc _nif_funcs[] = { __VA_ARGS__ };                                                                         \
    ERL_NIF_INIT(name, _nif_funcs, nullptr, nullptr, nullptr, nullptr)
