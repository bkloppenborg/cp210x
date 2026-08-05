obj-m += cp210x.o

# Manual builds: `make` from this directory.
# DKMS / kbuild sets KERNELRELEASE and invokes with M=...
ifeq ($(KERNELRELEASE),)
KVERSION ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVERSION)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

.PHONY: all clean
endif
