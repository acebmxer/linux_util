#!/bin/bash

# ============================================================================
# Linux Utilities - System Module
# Provides system helper functions used across all modules
# ============================================================================

# Helper functions for system setup
# NOTE: run_as_root passes its arguments as a single string to sh -c.
# Arguments containing spaces, quotes, or special characters will be
# subject to word-splitting by sh. For commands with complex quoting,
# use 'sudo bash -c "..."' directly instead of this helper.
run_as_root() { sudo -E sh -c "$*"; }
info()  { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn()  { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
error() { printf '\e[31m[ERROR]\e[0m %s\n' "$*" >&2; }
