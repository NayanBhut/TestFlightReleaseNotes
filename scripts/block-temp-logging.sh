#!/bin/sh
# Guard: keeps the temporary debug marker (e.g. live-token API logging in
# APIManager.swift) from ever being pushed or merged.
#
# Install (per clone/worktree — git does not sync hooks):
#   cp scripts/block-temp-logging.sh "$(git rev-parse --git-dir)/hooks/pre-commit"
#   cp scripts/block-temp-logging.sh "$(git rev-parse --git-dir)/hooks/pre-push"
#   chmod +x "$(git rev-parse --git-dir)/hooks/pre-commit" "$(git rev-parse --git-dir)/hooks/pre-push"
#
# Behavior:
#   pre-commit: fails if the staged diff ADDS the marker to any swift
#     file. Unrelated commits pass; the removal commit passes (it only
#     deletes marker lines).
#   pre-push: fails if the pushed tip tree still carries the marker
#     anywhere — the backstop that keeps it off the remote for good.
# Bypass (emergency only): git commit/push --no-verify. Don't.
#
# NOTE: the marker literal below is split across quotes so this script
# does not match its own grep.

MARKER="TEMPORARY DEBUG"" AID"

fail() {
    echo "BLOCKED by $1: '$MARKER' still present."
    echo "Remove the temporary debug logging first (see APIManager.swift), then retry."
    exit 1
}

case "$(basename "$0")" in
    pre-push)
        while read -r _local_ref local_sha _remote_ref _remote_sha; do
            case "$local_sha" in
                0000000000000000000000000000000000000000) continue ;;
            esac
            if git grep -q "$MARKER" "$local_sha" -- '*.swift'; then
                fail "pre-push"
            fi
        done
        exit 0
        ;;
    *)
        if git diff --cached -- '*.swift' | grep "^+" | grep -v "^+++" | grep -q "$MARKER"; then
            fail "pre-commit"
        fi
        exit 0
        ;;
esac
