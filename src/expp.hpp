#pragma once
#include "casts.hpp"
#include "ext_types.hpp"
#include "generator.hpp"
#include "resource.hpp"
#include "yielding.hpp"
#include <erl_nif.h>
#include <optional>
#include <utility>


template <typename T>
struct function_traits;

template <typename R, typename... Args, bool IsNoexcept>
struct function_traits<R (*)(Args...) noexcept(IsNoexcept)>
{
    using func_type = R(Args...) noexcept(IsNoexcept);
    using return_type = R;
    static constexpr size_t nargs = sizeof...(Args);

    template <func_type fn, std::size_t... I>
    constexpr static R apply_impl(ErlNifEnv* env, const ERL_NIF_TERM argv[], std::index_sequence<I...>)
    {
        return fn(type_cast<std::decay_t<Args>>::load(env, argv[I])...);
    }

    template <func_type fn>
    constexpr static R apply(ErlNifEnv* env, const ERL_NIF_TERM argv[])
    {
        return apply_impl<fn>(env, argv, std::make_index_sequence<nargs> {});
    }

    constexpr static bool any_args_by_refenence()
    {
        return (... || std::is_reference_v<Args>);
    }

    template <typename U>
    constexpr static bool any_args_has_type()
    {
        return (... || std::is_same_v<Args, U>);
    }
};


template <typename GeneratorType>
ERL_NIF_TERM coroutine_step_impl(GeneratorType& coro, ErlNifEnv* env)
{
    try
    {
        if (auto& out = *std::begin(coro); out)
        {
            auto ret = type_cast<std::decay_t<decltype(*out)>>::handle(env, *out);
            return ret;
        }
        else
            return 0;  // slightly hacky, indicates that it needs to be scheduled for another step
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


template <typename GeneratorType>
ERL_NIF_TERM coroutine_step(ErlNifEnv* env, int, const ERL_NIF_TERM argv[])
{
    auto coroutine_resource = type_cast<yielding_resource_t>::load(env, argv[0]);
    auto& coro = coroutine_resource.get<GeneratorType>();

    if (ERL_NIF_TERM step_result = coroutine_step_impl(coro, env); step_result)
        return step_result;
    else
        return enif_schedule_nif(env, "coroutine_step", 0, coroutine_step<GeneratorType>, 1, argv);
}


template <auto fn>
constexpr ERL_NIF_TERM wrapper(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    using func_traits = function_traits<decltype(fn)>;

    if (argc != func_traits::nargs)
        return enif_make_badarg(env);

    try
    {
        auto ret = func_traits::template apply<fn>(env, argv);

        using return_type = typename func_traits::return_type;  // aka GeneratorType
        if constexpr (is_yielding_v<return_type>)
        {
            // Do some type-checking to make sure we don't run into trouble:
            // Because generator functions can be resumed, they cannot take
            // 1. arguments by reference (the original stack is gone when it's resumed)
            // 2. arguments of type binary (the data pointer might be invalidated when it's resumed)
            static_assert(
                !func_traits::any_args_by_refenence(), "generator functions cannot have pass-by-reference arguments");
            static_assert(
                !func_traits::template any_args_has_type<binary>(),
                "generator functions cannot have arguments of type binary");

            // try to step the generator one time
            if (auto step_output = coroutine_step_impl(ret, env); step_output)
                return step_output;
            else
            {
                // allocate a new resource for the generator and schedule it for execution later
                void* buf = enif_alloc_resource(yielding_resource_t::resource_type, sizeof(ret));
                new (buf) decltype(ret) { std::move(ret) };
                ERL_NIF_TERM out[] = { enif_make_resource(env, buf) };
                return enif_schedule_nif(env, "coroutine_step", 0, coroutine_step<return_type>, 1, out);
            }
        }
        else
        {
            return type_cast<std::decay_t<decltype(ret)>>::handle(env, std::move(ret));
        }
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


enum class DirtyFlags
{
    NotDirty = 0,
    DirtyCpu = ERL_NIF_DIRTY_JOB_CPU_BOUND,
    DirtyIO = ERL_NIF_DIRTY_JOB_IO_BOUND,
};


template <auto fn, DirtyFlags dirty_flag>
constexpr ErlNifFunc def_impl(const char* name)
{
    ErlNifFunc entry = {
        name,
        function_traits<decltype(fn)>::nargs,
        wrapper<fn>,
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
#define DEF2(fn, dirty_flag) def_impl<fn, dirty_flag>(#fn)
#define DEF3(fn, name, dirty_flag) def_impl<fn, dirty_flag>(name)
#define GET_MACRO(_1, _2, _3, NAME, ...) NAME
#define def(...) GET_MACRO(__VA_ARGS__, DEF3, DEF2, UNUSED)(__VA_ARGS__)


#define MODULE(NAME, LOAD, UPGRADE, UNLOAD, ...)                                                                       \
    ErlNifFunc _nif_funcs[] = { __VA_ARGS__ };                                                                         \
    ERL_NIF_INIT(NAME, _nif_funcs, LOAD, nullptr, UPGRADE, UNLOAD)
