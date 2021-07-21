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
    static constexpr bool is_noexcept = IsNoexcept;

    template <func_type fn, std::size_t... I>
    constexpr static R
    apply_impl(ErlNifEnv* env, const ERL_NIF_TERM argv[], std::index_sequence<I...>) noexcept(IsNoexcept)
    {
        return fn(type_cast<std::decay_t<Args>>::load(env, argv[I])...);
    }

    template <func_type fn>
    constexpr static R apply(ErlNifEnv* env, const ERL_NIF_TERM argv[]) noexcept(IsNoexcept)
    {
        return apply_impl<fn>(env, argv, std::make_index_sequence<nargs> {});
    }
};


template <typename Fn, Fn fn>
constexpr ERL_NIF_TERM
wrapper(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) noexcept(function_traits<Fn>::is_noexcept)
{
    using func_traits = function_traits<Fn>;

    if constexpr (func_traits::is_noexcept)
    {
        auto ret = func_traits::template apply<fn>(env, argv);
        return type_cast<std::decay_t<decltype(ret)>>::handle(env, std::move(ret));
    }

    else
    {
        try
        {
            auto ret = func_traits::template apply<fn>(env, argv);
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
}


enum class DirtyFlags
{
    NotDirty = 0,
    DirtyCpu = ERL_NIF_DIRTY_JOB_CPU_BOUND,
    DirtyIO = ERL_NIF_DIRTY_JOB_IO_BOUND,
};


template <typename Fn, Fn fn, DirtyFlags dirty_flag>
constexpr ErlNifFunc def_impl(const char* name)
{
    ErlNifFunc entry = {
        name,
        function_traits<Fn>::nargs,
        wrapper<Fn, fn>,
        static_cast<int>(dirty_flag),
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
#define DEF2(fn, dirty_flag) def_impl<decltype(&fn), fn, dirty_flag>(#fn)
#define DEF3(fn, name, dirty_flag) def_impl<decltype(&fn), fn, dirty_flag>(name)
#define GET_MACRO(_1, _2, _3, NAME, ...) NAME
#define def(...) GET_MACRO(__VA_ARGS__, DEF3, DEF2, UNUSED)(__VA_ARGS__)


#define MODULE(name, ...)                                                                                              \
    ErlNifFunc _nif_funcs[] = { __VA_ARGS__ };                                                                         \
    ERL_NIF_INIT(name, _nif_funcs, nullptr, nullptr, nullptr, nullptr)
