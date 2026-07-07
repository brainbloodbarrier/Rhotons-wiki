# Tests

Test suite for the autoresearch quality-gate scripts (`lib/*.sh`, the
post-commit hook) and the deterministic Python extraction tooling. The shell
scripts are the code CLAUDE.md defines campaign "failure" by (guard exit 1,
negative score delta).

## Run

```sh
tests/run-bats.sh                         # whole bats suite (shell)
tests/run-bats.sh tests/bats/verify.bats  # one file
python3 -m pytest tests/python -q         # python suite
```

Shell suite requires `bats` (bats-core >= 1.5) and `jq`:
`apt-get install -y bats jq` / `brew install bats-core jq`.
Python suite: `pip install -r tests/python/requirements.txt`.
CI runs both plus shellcheck on every PR (`.github/workflows/tests.yml`),
and a non-blocking `guard-canary` job that runs the guard against the real
vaults for drift visibility.

## Layout — shell (`bats/`)

- `verify.bats` — **freezes the v1 score formula** (125+ baseline rows in
  `.autoresearch/*/results.tsv` depend on it) and pins its documented
  quirks: link *lines* not occurrences; `index.md`/`log.md` count toward
  words but not pages. If these fail after editing verify, the edit
  changed every existing baseline — revert the edit, don't "fix" the test.
- `guard-*.bats` — detection, allowlist suppression, baseline regression
  (exit-code contract 0/1/2, incl. exit-2-beats-exit-1 precedence),
  cross-wiki references (`[[wiki:basename]]` + markdown cross-links), and
  the JSON/TSV output shapes parsed by the post-commit hook.
- `crossmap-generate.bats` — dry-run purity, normalized `pages_index` keys,
  duplicate-basename lists, bridges preservation, idempotence.
- `crosswiki-migrate.bats` — the vault-WRITING script: dry-run leaves the
  vault byte-identical, apply rewrites only uniquely-resolvable links
  (aliases/anchors preserved), ambiguous/unresolved skipped and reported,
  second apply is a no-op.
- `guard-bootstrap-allowlist.bats` — the round-trip property: bootstrap on
  a dirty vault ⇒ plain guard exits 0 on the same HEAD; `--merge`; exact
  violation-string capture.
- `campaign-status.bats` — TSV shape and the target_met rule.
- `post-commit-hook.bats` — always exits 0 (advisory), only speaks on
  `autoresearch/*` branches.
- `test_helper.bash` — builds a hermetic sandbox repo per test in
  `$BATS_TEST_TMPDIR` (guard/verify locate the repo root from their own
  script path, resolve-wiki walks up from `$PWD`; the sandbox satisfies
  both and keeps side effects out of the real repo).

## Layout — fixtures (`fixtures/`)

- `vault-clean` passes every check including `--strict --quality`;
- `vault-broken` has exactly one instance of each violation class;
- `vault-scored` has hand-countable words/links — its expected scores
  (v1 = 37, v2 = 39) are derived line-by-line in `verify.bats`. If you
  edit any fixture file, update that arithmetic; the friction is the
  point.

Cross-wiki and migration tests build their multi-wiki sandboxes inline and
generate `crossmap.json` with the real `lib/crossmap-generate.sh`.

## Layout — python (`python/`)

`conftest.py` loads modules by file path via `importlib` (tool dirs are
hyphenated; two files are named `preflight.py`) under unique aliases.
Covered: `datalab-augment/_shared.py` (frontmatter parser shared by three
tools), `map_chapters.py`, `attribute_figures.py` (synthetic chapter trees,
no API), `page_ranges.py` (stubbed pypdf `Destination`), the pure helpers
of both ~900-line Datalab convert clients, `cleanup_images.py`, and
`nsatlas_inventory.py`. Network paths (submit/poll) are intentionally
untested; the `.skills/` meta-tooling is out of scope.
