# Windows-only — runs from PowerShell, cmd, or Git Bash.
# macOS / Linux users: use bin/dotfiles (this Makefile hard-fails there).

ifneq ($(OS),Windows_NT)
  $(error This Makefile is Windows-only. Use bin/dotfiles on macOS/Linux.)
endif

# Force Git Bash for recipes regardless of host shell (PowerShell, cmd, Git Bash).
# Plain `bash.exe` on PATH often resolves to WSL bash, which can't run these recipes,
# so we derive the Git Bash path from `git --exec-path` (works for Git for Windows
# and scoop installs alike). Requires git on PATH.
GIT_EXEC := $(shell git --exec-path 2>nul)
ifeq ($(GIT_EXEC),)
  $(error git not found on PATH. Install Git for Windows: scoop install git)
endif
SHELL := $(GIT_EXEC)/../../../bin/bash.exe
.SHELLFLAGS := -c

# HOME may be unset in cmd/PowerShell; fall back to USERPROFILE.
HOME ?= $(USERPROFILE)

DOTFILES   := $(CURDIR)
CONFIG_DIR := $(DOTFILES)/config
TARGET     := $(HOME)/.config
CLAUDE_TGT := $(HOME)/.claude

# Auto-discover. Skip macOS-only daemons + the special-cased claude/.
EXCLUDE      := claude skhd yabai
PACKAGES     := $(filter-out $(EXCLUDE),$(notdir $(wildcard $(CONFIG_DIR)/*)))
CLAUDE_FILES := $(notdir $(wildcard $(CONFIG_DIR)/claude/*))

export MSYS = winsymlinks:nativestrict

.DEFAULT_GOAL := help
.PHONY: help link unlink verify

help:           ## list targets and discovered tools
	@awk 'BEGIN{FS=":.*##"} /^[a-z-]+:.*##/ {printf "  %-10s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

link:           ## create / refresh all symlinks (idempotent — safe to re-run)
	@tmp=$$(mktemp); ln -s "$$tmp" "$$tmp.lnk" 2>/dev/null; \
	  if [ ! -L "$$tmp.lnk" ]; then \
	    rm -f "$$tmp" "$$tmp.lnk"; \
	    echo "  cannot link — native symlinks unavailable."; \
	    echo "  Enable Windows Developer Mode: Settings -> Privacy & security -> For developers"; \
	    exit 1; \
	  fi; \
	  rm -f "$$tmp" "$$tmp.lnk"
	@mkdir -p "$(TARGET)" "$(CLAUDE_TGT)"
	@for pkg in $(PACKAGES); do \
	  dst="$(TARGET)/$$pkg"; src="$(CONFIG_DIR)/$$pkg"; \
	  if [ -L "$$dst" ]; then rm -f "$$dst"; \
	  elif [ -e "$$dst" ]; then echo "  SKIP  $$dst exists and is not a symlink"; continue; fi; \
	  ln -s "$$src" "$$dst" && echo "  link  $$dst -> $$src"; \
	done
	@for f in $(CLAUDE_FILES); do \
	  dst="$(CLAUDE_TGT)/$$f"; src="$(CONFIG_DIR)/claude/$$f"; \
	  if [ -L "$$dst" ]; then rm -f "$$dst"; \
	  elif [ -e "$$dst" ]; then echo "  SKIP  $$dst exists and is not a symlink"; continue; fi; \
	  ln -s "$$src" "$$dst" && echo "  link  $$dst -> $$src"; \
	done

unlink:         ## remove every symlink we created (only touches symlinks)
	@for pkg in $(PACKAGES); do \
	  dst="$(TARGET)/$$pkg"; \
	  [ -L "$$dst" ] && rm -f "$$dst" && echo "  rm    $$dst"; \
	done; true
	@for f in $(CLAUDE_FILES); do \
	  dst="$(CLAUDE_TGT)/$$f"; \
	  [ -L "$$dst" ] && rm -f "$$dst" && echo "  rm    $$dst"; \
	done; true

verify:         ## report status of every expected link (OK / MISSING / STALE / CONFLICT)
	@status=0; \
	for pkg in $(PACKAGES); do \
	  dst="$(TARGET)/$$pkg"; src="$(CONFIG_DIR)/$$pkg"; \
	  if [ -L "$$dst" ]; then \
	    if [ "$$dst" -ef "$$src" ]; then echo "  OK        $$dst"; \
	    else echo "  STALE     $$dst -> $$(readlink "$$dst")"; status=1; fi; \
	  elif [ -e "$$dst" ]; then echo "  CONFLICT  $$dst (not a symlink)"; status=1; \
	  else echo "  MISSING   $$dst"; status=1; fi; \
	done; \
	for f in $(CLAUDE_FILES); do \
	  dst="$(CLAUDE_TGT)/$$f"; src="$(CONFIG_DIR)/claude/$$f"; \
	  if [ -L "$$dst" ]; then \
	    if [ "$$dst" -ef "$$src" ]; then echo "  OK        $$dst"; \
	    else echo "  STALE     $$dst -> $$(readlink "$$dst")"; status=1; fi; \
	  elif [ -e "$$dst" ]; then echo "  CONFLICT  $$dst (not a symlink)"; status=1; \
	  else echo "  MISSING   $$dst"; status=1; fi; \
	done; \
	exit $$status
