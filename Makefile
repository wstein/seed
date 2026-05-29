# Makefile for Elixir workspaces.
#
# Provides a normalized interface for Mix commands and native workspace
# tasks.
#
# Usage:
#   make          # compile the project
#   make build    # mix compile
#   make test     # mix test
#   make check    # mix format --check-formatted
#   make verify   # check + test + build
#   make certify  # verify
#   make clean    # remove generated output
#   make notes    # show the notes directory path
#
MIX ?= mix
CLEAN_DIR ?= dist

.PHONY: all build test check verify certify clean notes help
all: build

build: ## Compile the Elixir project.
	$(MIX) compile

test: ## Run Elixir tests.
	$(MIX) test

check: ## Verify Elixir sources are formatted.
	$(MIX) format --check-formatted

verify: ## Run the standard Elixir quality gate.
	@$(MAKE) check && $(MAKE) test && $(MAKE) build

certify: ## Run the local Elixir release gate.
	@$(MAKE) verify

clean: ## Remove generated output files.
	$(MIX) clean
	rm -rf "$(CLEAN_DIR)" _build cover

notes: ## Print the notes directory path.
	@printf "Notes directory: notes\n"

help: ## Show available targets.
	@printf "Available targets:\n  build test check verify certify clean notes\n"
