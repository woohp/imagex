#pragma once
#include "casts.hpp"
#include <map>
#include <stdexcept>
#include <unordered_map>
#include <vector>


template <typename T>
concept InnerType = (std::is_move_constructible_v<T> || std::is_copy_constructible_v<T>)
    && (type_castable<T> || std::is_same_v<T, std::byte>);


template <InnerType T>
struct type_cast<std::vector<T>>
{
private:
    typedef std::decay_t<T> item_type;

public:
    constexpr static std::vector<T> load(ErlNifEnv* env, const ERL_NIF_TERM term)
    {
        if constexpr ((std::is_integral_v<T> && sizeof(T) == 1) || std::is_same_v<T, std::byte>)
        {
            ErlNifBinary binary_info;
            if (!enif_inspect_binary(env, term, &binary_info))
                throw std::invalid_argument("invalid string");
            auto begin = reinterpret_cast<const T*>(binary_info.data);
            auto end = begin + binary_info.size;
            return std::vector<T>(begin, end);
        }
        else
        {
            unsigned len = 0;
            if (!enif_get_list_length(env, term, &len))
                throw std::invalid_argument("invalid vector");

            std::vector<T> items;
            items.reserve(len);
            ERL_NIF_TERM list_term = term;
            for (unsigned i = 0; i < len; i++)
            {
                ERL_NIF_TERM head, tail;
                enif_get_list_cell(env, list_term, &head, &tail);
                items.push_back(type_cast<item_type>::load(env, head));
                list_term = tail;
            }

            return items;
        }
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const std::vector<T>& items) noexcept
    {
        if constexpr ((std::is_integral_v<T> && sizeof(T) == 1) || std::is_same_v<T, std::byte>)
        {
            ErlNifBinary binary_info;
            enif_alloc_binary(items.size(), &binary_info);
            std::copy_n(items.data(), items.size(), binary_info.data);
            return enif_make_binary(env, &binary_info);
        }
        else
        {
            std::vector<ERL_NIF_TERM> nif_terms;
            nif_terms.reserve(items.size());

            for (const auto& item : items)
                nif_terms.push_back(type_cast<item_type>::handle(env, item));

            return enif_make_list_from_array(env, nif_terms.data(), nif_terms.size());
        }
    }
};


template <InnerType K, InnerType V>
struct type_cast<std::unordered_map<K, V>>
{
private:
    typedef std::decay_t<K> key_type;
    typedef std::decay_t<V> value_type;
    typedef std::unordered_map<key_type, value_type> map_type;

public:
    constexpr static map_type load(ErlNifEnv* env, const ERL_NIF_TERM term)
    {
        map_type _map;
        std::size_t size;
        if (!enif_get_map_size(env, term, &size))
            throw std::invalid_argument("invalid map");
        _map.reserve(size);

        ErlNifMapIterator iter;
        if (!enif_map_iterator_create(env, term, &iter, ERL_NIF_MAP_ITERATOR_FIRST))
            throw std::invalid_argument("invalid map");

        ERL_NIF_TERM key, value;
        while (enif_map_iterator_get_pair(env, &iter, &key, &value))
        {
            _map.emplace(type_cast<key_type>::load(env, key), type_cast<value_type>::load(env, value));
            enif_map_iterator_next(env, &iter);
        }

        return _map;
    }

    constexpr static ERL_NIF_TERM handle(ErlNifEnv* env, const map_type& _map) noexcept
    {
        ERL_NIF_TERM map_term = enif_make_new_map(env);

        for (const auto& item : _map)
        {
            ERL_NIF_TERM new_map_term;
            ERL_NIF_TERM key_term = type_cast<key_type>::handle(env, item.first);
            ERL_NIF_TERM value_term = type_cast<value_type>::handle(env, item.second);
            enif_make_map_put(env, map_term, key_term, value_term, &new_map_term);
            map_term = new_map_term;
        }

        return map_term;
    }
};


template <InnerType K, InnerType V>
struct type_cast<std::map<K, V>>
{
private:
    typedef std::decay_t<K> key_type;
    typedef std::decay_t<V> value_type;
    typedef std::map<key_type, value_type> map_type;

public:
    constexpr static map_type load(ErlNifEnv* env, const ERL_NIF_TERM term)
    {
        map_type _map;
        std::size_t size;
        if (!enif_get_map_size(env, term, &size))
            throw std::invalid_argument("invalid map");
        _map.reserve(size);

        ErlNifMapIterator iter;
        if (!enif_map_iterator_create(env, term, &iter, ERL_NIF_MAP_ITERATOR_FIRST))
            throw std::invalid_argument("invalid map");

        ERL_NIF_TERM key, value;
        while (enif_map_iterator_get_pair(env, &iter, &key, &value))
        {
            _map.emplace(type_cast<key_type>::load(env, key), type_cast<value_type>::load(env, value));
            enif_map_iterator_next(env, &iter);
        }

        return _map;
    }

    constexpr static ERL_NIF_TERM handle(ErlNifEnv* env, const map_type& _map) noexcept
    {
        ERL_NIF_TERM map_term = enif_make_new_map(env);

        for (const auto& item : _map)
        {
            ERL_NIF_TERM new_map_term;
            ERL_NIF_TERM key_term = type_cast<key_type>::handle(env, item.first);
            ERL_NIF_TERM value_term = type_cast<value_type>::handle(env, item.second);
            enif_make_map_put(env, map_term, key_term, value_term, &new_map_term);
            map_term = new_map_term;
        }

        return map_term;
    }
};
