#pragma once
#include "casts.hpp"
#include <array>
#include <map>
#include <stdexcept>
#include <unordered_map>
#include <vector>


template <typename T>
struct type_cast<std::vector<T>>
{
private:
    typedef std::decay_t<T> item_type;

public:
    constexpr static std::vector<T> load(ErlNifEnv* env, const ERL_NIF_TERM term)
    {
        if constexpr (std::is_same_v<T, uint8_t> || std::is_same_v<T, int8_t> || std::is_same_v<T, std::byte>)
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
            const ERL_NIF_TERM* tup_array;
            int arity;
            if (!enif_get_tuple(env, term, &arity, &tup_array))
                throw std::invalid_argument("invalid vector/tuple");

            std::vector<T> items;
            items.reserve(arity);
            for (int i = 0; i < arity; i++)
                items.push_back(type_cast<item_type>::load(env, tup_array[i]));

            return items;
        }
    }

    static ERL_NIF_TERM handle(ErlNifEnv* env, const std::vector<T>& items) noexcept
    {
        if constexpr (std::is_same_v<T, uint8_t> || std::is_same_v<T, int8_t> || std::is_same_v<T, std::byte>)
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

            return enif_make_tuple_from_array(env, nif_terms.data(), nif_terms.size());
        }
    }
};


template <typename T, std::size_t N>
struct type_cast<std::array<T, N>>
{
private:
    typedef std::decay_t<T> item_type;
    typedef std::array<item_type, N> array_type;

public:
    constexpr static array_type load(ErlNifEnv* env, const ERL_NIF_TERM term)
    {
        const ERL_NIF_TERM* tup_array;
        int arity;
        if (!enif_get_tuple(env, term, &arity, &tup_array))
            throw std::invalid_argument("invalid array/tuple");
        if (arity != N)
            throw std::invalid_argument("invalid array/tuple");

        array_type items;
        for (int i = 0; i < arity; i++)
            items.push_back(type_cast<item_type>::load(env, tup_array[i]));

        return items;
    }

    constexpr static ERL_NIF_TERM handle(ErlNifEnv* env, const array_type& items) noexcept
    {
        std::array<ERL_NIF_TERM, N> nif_terms;
        for (std::size_t i = 0; i < N; i++)
            nif_terms[i] = type_cast<item_type>::handle(env, items[i]);

        return enif_make_tuple_from_array(env, nif_terms.data(), N);
    }
};


template <typename K, typename V>
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


template <typename K, typename V>
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
