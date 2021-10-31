package=example.ipkg
executable=example
idris2=idris2

.PHONY: build clean run dev

build:
	bash -c '$(idris2) --build $(package)'

clean:
	rm -rf build

run: build
	bash -c 'build/exec/$(executable)'

dev:
	find . -name '*.idr' | entr make run

