ENGINE=lualatex
FLAGS=-interaction=nonstopmode -halt-on-error -file-line-error
BUILD=build

.PHONY: all example reference test clean

all: example reference

example:
	mkdir -p $(BUILD)
	TEXINPUTS=.:src//: $(ENGINE) $(FLAGS) -output-directory=$(BUILD) examples/neopage-technical-article.tex
	TEXINPUTS=.:src//: $(ENGINE) $(FLAGS) -output-directory=$(BUILD) examples/neopage-technical-article.tex

reference:
	mkdir -p $(BUILD)
	TEXINPUTS=.:src//: $(ENGINE) $(FLAGS) -jobname=published-reference-profile -output-directory=$(BUILD) tests/019-published-reference-profile.tex

test:
	bash scripts/run-tests.sh

clean:
	rm -rf $(BUILD) tests/build
