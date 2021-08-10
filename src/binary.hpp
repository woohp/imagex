#pragma once
#include <algorithm>
#include <erl_nif.h>


template <typename T>
struct type_cast;


class binary : public ErlNifBinary
{
private:
    ERL_NIF_TERM _term = 0;

    friend struct type_cast<binary>;

    binary& operator=(const binary&) = default;

public:
    binary()
    {
        this->size = 0;
        this->data = nullptr;
    }

    explicit binary(size_t size)
    {
        enif_alloc_binary(size, this);
    }

    template <size_t N>
    explicit binary(const char (&str)[N])
    {
        enif_alloc_binary(N - 1, this);
        std::copy_n(str, N - 1, this->data);
    }

    binary(binary&& other)
    {
        this->operator=(std::move(other));
    }

    binary(const binary& other) = delete;

    ~binary()
    {
        if (!this->_term && this->data)
        {
            enif_release_binary(this);
            this->size = 0;
            this->data = nullptr;
        }
    }

    binary& operator=(binary&& other)
    {
        *this = other;

        other.size = 0;
        other.data = nullptr;
        other._term = 0;

        return *this;
    }
};


binary operator"" _binary(const char* s, std::size_t len)
{
    binary binary_info;
    enif_alloc_binary(len, &binary_info);
    std::copy_n(s, len, binary_info.data);
    return binary_info;
}
