MIX = mix
CFLAGS = -O3 -ansi -pedantic -Wall -Wextra -Wno-unused-parameter -std=c++23 -fvisibility=hidden

ERTS_INCLUDE_DIR ?= $(ERL_EI_INCLUDE_DIR)
ifeq ($(ERTS_INCLUDE_DIR),)
    ERTS_INCLUDE_DIR = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)
endif
CFLAGS += -I$(ERTS_INCLUDE_DIR) -I$(EXPP_INCLUDE_DIR)

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

priv/imagex.so: priv src/imagex.cpp
	$(CXX) $(CFLAGS) -shared $(LDFLAGS) -o $@ src/imagex.cpp -ljpeg -lpng -ljxl -ljxl_threads -lpoppler-cpp -ltiff -ltiffxx

priv:
	@mkdir -p priv

clean:
	$(MIX) clean
	$(RM) priv/imagex.so

fmt:
	find src -type f | xargs clang-format -i
	$(MIX) format
