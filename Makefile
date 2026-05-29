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
#   make lint     # mix credo --strict
#   make dialyzer # mix dialyzer
#   make verify   # check + lint + test + build + dialyzer
#   make certify  # verify
#   make clean    # remove generated output
#   make notes    # show the notes directory path
#
MIX ?= mix
CLEAN_DIR ?= dist

.PHONY: all build test check lint dialyzer verify certify clean notes help
all: build

build: ## Compile the Elixir project.
	$(MIX) compile

test: ## Run Elixir tests.
	$(MIX) test

check: ## Verify Elixir sources are formatted.
	$(MIX) format --check-formatted

lint: ## Run static code analysis.
	$(MIX) credo --strict

dialyzer: ## Run static type analysis.
	$(MIX) dialyzer

verify: ## Run the standard Elixir quality gate.
	@$(MAKE) check && $(MAKE) lint && $(MAKE) test && $(MAKE) build && $(MAKE) dialyzer

certify: ## Run the local Elixir release gate.
	@$(MAKE) verify

clean: ## Remove generated output files.
	$(MIX) clean
	rm -rf "$(CLEAN_DIR)" _build cover

notes: ## Print the notes directory path.
	@printf "Notes directory: notes\n"

help: ## Show available targets.
	@printf "Available targets:\n  build test check lint dialyzer verify certify clean notes\n"
