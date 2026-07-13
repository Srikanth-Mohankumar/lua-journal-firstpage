ENGINE=lualatex
FLAGS=-interaction=nonstopmode -halt-on-error -file-line-error
BUILD=build

.PHONY: example test clean

example:
	mkdir -p $(BUILD)
	TEXINPUTS=.:src//: $(ENGINE) $(FLAGS) -output-directory=$(BUILD) examples/neopage-technical-article.tex
	TEXINPUTS=.:src//: $(ENGINE) $(FLAGS) -output-directory=$(BUILD) examples/neopage-technical-article.tex

test:
	bash scripts/run-tests.sh

clean:
	rm -rf $(BUILD) tests/build
