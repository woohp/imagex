#pragma once
#include <string>


template<typename T>
struct type_cast;


struct atom
{
    explicit atom(const char* s): name(s)
    {}

    explicit atom(const std::string& s): name(s)
    {}

    atom(atom&& other): name(move(other.name))
    {}

    bool operator==(const atom& other) const
    {
        return this->name == other.name;
    }

    bool operator!=(const atom& other) const
    {
        return this->name != other.name;
    }

    std::string name;
};


atom operator"" _a(const char* s)
{
    return atom(s);
}
