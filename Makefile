MIX = mix
CFLAGS = -O3 -ansi -pedantic -Wall -Wextra -Wno-unused-parameter -std=c++2b

ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)
CFLAGS += -I$(ERLANG_PATH)

ifneq ($(OS), Windows_NT)
    CFLAGS += -fPIC

    ifeq ($(shell uname), Darwin)
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
    endif
endif

.PHONY: all imagex clean fmt

all: imagex

imagex:
	$(MIX) compile

priv/imagex.so: src/imagex.cpp
	$(CXX) $(CFLAGS) -shared $(LDFLAGS) -o $@ src/imagex.cpp -ljpeg -lpng -ljxl -ljxl_threads -lpoppler-cpp -ltiff -ltiffxx

clean:
	$(MIX) clean
	$(RM) priv/imagex.so

fmt:
	find src -type f | xargs clang-format -i
	$(MIX) format
