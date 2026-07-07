# Tests

Bats suite for the `lib/*.sh` autoresearch quality-gate scripts — the code
CLAUDE.md defines campaign "failure" by (guard exit 1, negative score delta).

## Run

```sh
tests/run-bats.sh                       # whole suite
tests/run-bats.sh tests/bats/verify.bats  # one file
```

Requires `bats` (bats-core >= 1.5) and `jq`:
`apt-get install -y bats jq` / `brew install bats-core jq`.
CI runs the suite plus shellcheck on every PR (`.github/workflows/tests.yml`).

## Layout

- `bats/` — test files, one per behavioral area:
  - `verify.bats` — **freezes the v1 score formula** (125+ baseline rows in
    `.autoresearch/*/results.tsv` depend on it) and pins its documented
    quirks: link *lines* not occurrences; `index.md`/`log.md` count toward
    words but not pages. If these fail after editing verify, the edit
    changed every existing baseline — revert the edit, don't "fix" the test.
  - `guard-*.bats` — detection, allowlist suppression, baseline regression
    (exit-code contract 0/1/2, incl. exit-2-beats-exit-1 precedence), and
    the JSON/TSV output shapes parsed by the post-commit hook.
  - `resolve-wiki.bats`, `constants.bats` — registry resolution exit codes
    (64/65/66) and `normalize_target`.
- `bats/test_helper.bash` — builds a hermetic sandbox repo per test in
  `$BATS_TEST_TMPDIR` (guard/verify locate the repo root from their own
  script path, resolve-wiki walks up from `$PWD`; the sandbox satisfies
  both and keeps side effects out of the real repo).
- `fixtures/` — synthetic vaults:
  - `vault-clean` passes every check including `--strict --quality`;
  - `vault-broken` has exactly one instance of each violation class;
  - `vault-scored` has hand-countable words/links — its expected scores
    (v1 = 37, v2 = 39) are derived line-by-line in `verify.bats`. If you
    edit any fixture file, update that arithmetic; the friction is the
    point.

## Follow-ups (not yet covered)

Phase 2: `crossmap-generate.sh`, `crosswiki-migrate.sh`,
`guard-bootstrap-allowlist.sh`, `campaign-status.sh`, the post-commit hook.
Phase 3: pytest for the deterministic Python under
`rhoton-wiki/tools/` and `nsatlas-wiki/tools/`.
