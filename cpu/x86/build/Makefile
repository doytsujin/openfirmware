OS := $(shell uname)

all: basefw.dic

.PHONY: FORCE all clean

.PRECIOUS: builder.dic

../${OS}/forth:
	@make -C ../${OS} forth

build: ../${OS}/forth
	@ln -sf ../${OS}/forth $@

%.dic: FORCE build
	./build $@

builder.dic: FORCE build
	-[ ! -f builder.sav ] && cp builder.dic builder.sav
	./build builder.dic

inflate.bin:
	make -C ../${OS} ../build/inflate.bin

# Don't use *.dic so as not to remove builder.dic
clean:
	rm -f tools.dic kernel.dic basefw.dic
	rm -f *.tag *.log headers *~ inflate.bin build
	make -C ../${OS} clean
