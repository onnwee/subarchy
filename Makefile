# Subarchy build and checks. `make verify` is what CI runs.
GO ?= go
BUILD := build
VERSION ?= 0.0.0
LDFLAGS := -X git.subcult.tv/subculture-collective/subarchy/internal/dispatch.Version=$(VERSION)
SHELL_SCRIPTS := $(shell git ls-files '*.sh' 'bin/subcult-*' 2>/dev/null)

.PHONY: verify fmt-check vet test build smoke shellcheck docs-check package iso iso-test install-test hypr-check

verify: fmt-check vet test build smoke shellcheck docs-check hypr-check

fmt-check:
	@out=$$(gofmt -l $$(git ls-files '*.go')); if [ -n "$$out" ]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi

vet:
	$(GO) vet ./...

test:
	$(GO) test -race -count=1 ./...

build:
	mkdir -p $(BUILD)
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags '$(LDFLAGS)' -o $(BUILD)/ ./cmd/...

smoke: build
	tools/test/dispatcher-smoke.sh $(BUILD)/subcult
	tools/test/power-auto-test.sh
	tools/test/gpu-test.sh

shellcheck:
	@if [ -n "$(SHELL_SCRIPTS)" ]; then shellcheck -x $(SHELL_SCRIPTS); fi

docs-check:
	python3 tools/obsidian/check-vault.py
	python3 -m py_compile tools/inventory/collect.py tools/obsidian/check-vault.py tools/obsidian/install-plugins.py tools/iso/boot-test.py tools/iso/install-test.py tools/iso/vmlib.py

# Checks the Hyprland Lua defaults where Hyprland is installed (not in CI).
hypr-check:
	@if command -v Hyprland >/dev/null; then \
	  for c in default/hypr/user-hyprland.lua default/sddm/hyprland.lua; do \
	    SUBCULT_PATH=$(CURDIR) Hyprland --verify-config -c $$c 2>&1 | grep -qx 'config ok' || { echo "hypr-check: $$c"; exit 1; }; \
	  done; echo "hypr-check: ok"; \
	else echo "hypr-check: Hyprland not installed, skipped"; fi

# Builds the subarchy pacman package and checks its contents (Arch only).
package:
	tools/test/package-test.sh

# Live ISO: needs archiso and sudo (see iso/README.md).
iso:
	tools/iso/build.sh

# Boots the newest ISO in QEMU and checks it over the serial console.
iso-test:
	python3 tools/iso/boot-test.py "$$(ls -t $(BUILD)/iso/subarchy-*.iso | head -1)"

# Installs from the newest ISO into a VM disk, then boots and checks it.
install-test:
	python3 tools/iso/install-test.py "$$(ls -t $(BUILD)/iso/subarchy-*.iso | head -1)"
