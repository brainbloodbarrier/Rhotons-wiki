#!/bin/bash
# lib/constants.sh — shared constants sourced by lib/*.sh scripts.
#
# This file is meant to be `source`d, not executed. It must not export
# any state other than read-only variables. Do not call `set` here —
# the consumer script owns its own shell options.
#
# Consumers: autoresearch-guard.sh, autoresearch-verify.sh, campaign-status.sh.

# Six typed relation pairs expressed in frontmatter. Update here when the
# ontology changes; every guard/verify/status script picks it up via source.
# Matching regex is anchored to start-of-line and expects `key:` form.
# shellcheck disable=SC2034  # consumed via `source`, shellcheck can't see callers
BREADCRUMB_RE='^(parent|child|branch-of|branches|innervates|innervated-by|traverses|traversed-by|approach-to|approached-via|drains-to|drained-by):'
