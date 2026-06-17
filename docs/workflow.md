# CI And Release Workflow

## Branches

- `master`: stable accepted history.
- `staging`: integration queue for reviewed PRs that passed correctness.
- `release/<version>`: cut from a known-good staging commit.
- PR branches: individual changes.
- fix PR branches: targeted fixes for staging or release failures.

## Correctness

Correctness runs on every PR and is intended to be reproducible locally. If a
developer cannot run a required check locally, it should not be required in this
stage.

Required checks:

- `correctness-format`: Ironworks Nix formatting.
- `correctness-lint`: fast source text hygiene that does not require `.git`.
- `correctness-linux-unit`: native Linux package build with unit tests.
- `correctness-regtest-smoke`: installed `bitcoind` starts, exposes the regtest
  IPC socket, and shuts down cleanly through `bitcoin-cli`.

Explicitly excluded:

- sanitizers
- fuzzing
- Valgrind
- IBD
- benchmarks
- previous-release compatibility
- broad cross-platform matrix

Local command:

```sh
nix build .#checks.x86_64-linux.correctness \
  --override-input node path:/path/to/2140-node \
  --print-build-logs
```

## Promotion To Staging

A PR is eligible for staging when:

- correctness is green
- the PR has required review approval
- a maintainer applies `ready-for-staging`

Promotion is performed with:

```sh
nix run .#promote-to-staging -- \
  --repo 2140-dev/bitcoin \
  --pr 123 \
  --target staging \
  --push
```

Without `--push`, the command prepares the merge locally and stops before
publishing it.

Staging merge commits must include:

- PR number
- PR head SHA
- target branch
- promotion timestamp

## Staging

Staging is an integration queue, not a release branch. It should stay mostly
green so incoming staged changes continue receiving useful signal.

Required staging jobs:

- full native package build
- full unit tests
- installed regtest smoke
- benchmark sanity check
- fuzz binary smoke

Heavy staging jobs:

- ASan/UBSan build and unit tests
- TSan build and unit tests
- MSan build-only until instrumented dependencies are packaged
- fuzz target inventory report
- valgrind fuzz smoke
- cross-platform package builds
- clang-tidy and iwyu reports

If staging fails:

- clear isolated culprit: open bug, revert staging merge, require a fix PR
- interaction bug: open staging bug, link suspected PRs, prefer fix PR or
  revert the smaller/riskier change
- infra/flaky bug: open infra bug and mark the affected job non-gating until
  signal is useful again

## Harden

Harden jobs run on a schedule against forge-green lock branches. They are not
PR checks and should not select mutable source refs directly.

Current scheduled outputs:

- `scheduled.required`
- `scheduled.ibd-small`
- `scheduled.previous-releases`
- `scheduled.fuzz-corpus`
- `scheduled.benchmark-artifact`
- `scheduled.benchmark-report`

The IBD, previous-release, and fuzz-corpus jobs currently validate metadata and
emit scaffold reports until fixture storage and schedules are approved. The
benchmark artifact is a Hydra-built closure that dedicated benchmark workers
can fetch from the signed cache. The benchmark report runs a small
machine-readable benchmark sample inside Hydra for packaging signal only; stable
performance history belongs on dedicated benchmark workers.

## Release

Release branches are cut from a known-good staging snapshot:

```sh
git checkout -b release/31.x <green-staging-sha>
```

Release jobs:

- hardened release package build
- installed regtest smoke from package outputs
- release manifest with Nix lock and checksums
- release checklist generated from the manifest
- future upgrade/downgrade fixtures
- future long fuzz budget
- future deterministic IBD replay

A commit is release-eligible only if it is contained in a green staging snapshot
or is a targeted release-branch fix that passed release CI.

The release checklist records the locked source, Ironworks, and nixpkgs inputs,
then requires explicit review of required harden reports and the benchmark
report before `stamp`.
