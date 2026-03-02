# Makefile for compiling turbotoken NIF
#
# Uses ERTS_INCLUDE_DIR from elixir_make.
# Links against the turbotoken shared library.

PRIV_DIR = priv
NIF_SO = $(PRIV_DIR)/turbotoken_nif.so

CFLAGS ?= -O2 -Wall -Wextra
CFLAGS += -I../../include -I$(ERTS_INCLUDE_DIR) -fPIC -shared

LDFLAGS += -L../../zig-out/lib -lturbotoken

ifeq ($(shell uname),Darwin)
	LDFLAGS += -undefined dynamic_lookup
endif

.PHONY: all clean

all: $(PRIV_DIR) $(NIF_SO)

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(NIF_SO): ../nif/turbotoken_nif.c ../../include/turbotoken.h
	$(CC) $(CFLAGS) -o $@ ../nif/turbotoken_nif.c $(LDFLAGS)

clean:
	rm -f $(NIF_SO)
