# Subarchy build and checks. `make verify` is what CI runs.
GO ?= go
BUILD := build
VERSION ?= 0.0.0
LDFLAGS := -X git.subcult.tv/subculture-collective/subarchy/internal/dispatch.Version=$(VERSION)
SHELL_SCRIPTS := $(shell git ls-files '*.sh' 'bin/subcult-*' 2>/dev/null)

.PHONY: verify fmt-check vet test build smoke shellcheck docs-check

verify: fmt-check vet test build smoke shellcheck docs-check

fmt-check:
	@out=$$(gofmt -l $$(git ls-files '*.go')); if [ -n "$$out" ]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi

vet:
	$(GO) vet ./...

test:
	$(GO) test -race -count=1 ./...

build:
	mkdir -p $(BUILD)
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags '$(LDFLAGS)' -o $(BUILD)/subcult ./cmd/subcult

smoke: build
	tools/test/dispatcher-smoke.sh $(BUILD)/subcult

shellcheck:
	@if [ -n "$(SHELL_SCRIPTS)" ]; then shellcheck -x $(SHELL_SCRIPTS); fi

docs-check:
	python3 tools/obsidian/check-vault.py
	python3 -m py_compile tools/inventory/collect.py tools/obsidian/check-vault.py tools/obsidian/install-plugins.py
