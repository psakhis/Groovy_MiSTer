# SPDX-License-Identifier: (GPL-2.0)
LIB_DIR = ../lib
#include $(LIB_DIR)/defines.mk

CC := /opt/arm/bin/arm-none-linux-gnueabihf-gcc.exe

all: common_params.o common_user_bpf_xdp.o

CFLAGS += -I$(LIB_DIR)/libbpf -I$(LIB_DIR)/libxdp -I$(LIB_DIR)/install/include

common_params.o: common_params.c common_params.h
	$(QUIET_CC)$(CC) $(CFLAGS) -c -o $@ $<

common_user_bpf_xdp.o: common_user_bpf_xdp.c common_user_bpf_xdp.h
	$(QUIET_CC)$(CC) $(CFLAGS) -c -o $@ $<

.PHONY: clean

clean:
	$(Q)rm -f *.o
