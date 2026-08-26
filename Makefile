all: build

build:
	make -C src/ all

install:
	make -C src/ install

test:
	bash tests/test-wrapper.sh

.PHONY: build install test
