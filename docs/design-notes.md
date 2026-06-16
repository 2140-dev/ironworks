# Design Notes

This file records the implementation context that is easy to lose between
passes. It should be updated when Ironworks or the CI model changes.

## Naming

The reusable Ironworks framework is intended to live at:

```text
2140-dev/ironworks
```

The first concrete 2140 deployment is intended to live at:

```text
2140-dev/saugus
```

Human-facing stage vocabulary:

- `spark`: fast PR correctness
- `forge`: staging integration
- `harden`: scheduled heavy validation
- `temper`: release candidate validation
- `stamp`: final release publication

The current Nix attribute names remain literal (`correctness`, `staging`,
`release`) because they are stable automation handles. The themed names are for
documentation, CI display names, and future user-facing wrappers.

## Repository Boundary

The source repository should continue to own CMake targets, CMake options,
tests, and install rules.

Ironworks is the reusable library/framework. It owns:

- pinned Nix dependencies
- project adapters
- package profiles
- CI stages
- Hydra job names
- reusable NixOS modules
- source workflow templates
- deployment templates
- library/API checks

Saugus is the first consumer deployment. It owns:

- host inventory
- NixOS host configurations
- disk layouts and hardware profiles
- Hydra project/jobset setup
- binary cache policy
- encrypted secret metadata
- staging and release lock branches
- benchmark worker fleet policy
- release artifact composition

This keeps the source tree from accumulating packaging-specific CI logic while
still letting CI build from exact source revisions. It also keeps the reusable
Ironworks framework free of 2140-specific hostnames, keys, cache names, and
operational state.

Ironworks is intended to support multiple node implementations. The public
flake API should expose reusable constructors and modules rather than requiring
consumers to depend on one hard-coded default project.

Target public outputs:

```text
lib.stages
lib.mkProject
lib.mkHydraJobsets
lib.mkStageChecks
lib.mkStageHydraJobs
lib.projectAdapters.<project-id>
nixosModules.hydra-controller
nixosModules.hydra-builder
nixosModules.benchmark-worker
nixosModules.github-runner
templates.source-workflow
templates.deployment
overlays.default
```

The current 2140 adapter should remain as the first bundled adapter at
`projects/2140-node`, but production evaluation should happen through Saugus:
Saugus pins the source tree, Ironworks revision, and nixpkgs revision, then
exports the concrete `hydraJobs` Hydra evaluates.

Ironworks owns the canonical stage catalog:

- `spark`
- `forge`
- `harden`
- `temper`
- `stamp`

Adapters own the concrete implementation of those stages. A project can start
with only a subset, but missing stages should be visible as unimplemented in
the library projection rather than silently absent from the domain model.
`lib.mkProject` records whether each stage is enabled, implemented, and active;
only active stage handles are exported for Hydra/check consumption.

## Stage Model

Correctness is the PR gate. It should stay fast enough and local enough that a
developer can run the same command before asking for review:

```sh
nix build .#checks.x86_64-linux.correctness \
  --override-input node path:/path/to/2140-node \
  --print-build-logs
```

Do not add checks to correctness if they require special infrastructure, long
wall-clock budgets, or broad fleet coverage. Sanitizers, fuzzing, IBD,
benchmarks, previous-release compatibility, and broad platform matrices belong
in staging or release.

Staging is the integration queue. It is where accepted PRs are tested together,
including the slower checks that find interaction bugs. Failures here should be
handled by fix PRs or staging reverts, not by letting staging remain broken for
long periods.

Release is cut from a known-good staging commit. Release branches should only
take commits that were already green in staging, or targeted release fixes that
pass release CI.

## Promotion Model

Promotion from PR to staging is intentionally explicit:

- PR correctness is green.
- Required review approval exists.
- Maintainer applies `ready-for-staging`.
- `apps/promote-to-staging.py` merges the PR head into `staging`.

The promotion merge commit records the PR number, PR head SHA, target branch,
and UTC promotion timestamp. This is what lets release managers later identify
which exact PR commits are contained in a green staging snapshot.

If staging fails after a promotion:

- isolated culprit: open a bug linked to the PR, revert the staging merge, and
  require a fix PR
- interaction bug: open a staging bug linking the suspected PRs, then prefer a
  fix PR or revert the smaller/riskier change
- infra/flaky job: open an infra bug and make the job non-gating until it has
  useful signal again

## Current Adapter Package Profiles

The 2140-node adapter currently builds these source profiles:

- `node-correctness`: daemon, CLI, GUI binary target, unit tests, no bench/fuzz
- `node-staging-full`: correctness plus bench, chainstate, kernel lib, kernel
  tests, and USDT support on Linux
- `node-fuzz`: libFuzzer-oriented fuzz binary
- `node-release`: hardened release package with man pages

The default package is `node-release`.

## 2140-Node Adapter Notes

The source tree is Bitcoin-Core-like but has a few packaging details to keep in
mind:

- `bitcoin-cli` shutdown is exercised through the node IPC socket in the
  regtest smoke test. The smoke test does not use RPC.
- The installed regtest smoke asserts that `regtest/node.sock` exists before
  stopping the daemon.
- Fuzz builds produce `bin/fuzz`, but the CMake install step may not install it.
  The Nix package explicitly installs it to `$out/libexec/fuzz`.
- `libbitcoinkernel.pc` can be generated with absolute Nix install paths
  incorrectly prefixed by `${prefix}`. The package normalizes the installed
  `libdir` and `includedir` lines in `postInstall`.
- `script_assets_tests` is skipped by the upstream CTest run in the current
  local build.

## Validation Snapshot

The initial implementation was validated against the local source checkout at
`/home/josie/2140-node` with:

```sh
nix fmt
nix flake check --no-build --all-systems --print-build-logs
nix build .#checks.x86_64-linux.correctness \
  --override-input node path:/home/josie/2140-node \
  --print-build-logs
nix build .#checks.x86_64-linux.staging \
  --override-input node path:/home/josie/2140-node \
  --print-build-logs
nix build .#checks.x86_64-linux.release-manifest \
  --override-input node path:/home/josie/2140-node \
  --print-build-logs
```

Observed local results:

- correctness: package build, 322 CTest entries, installed regtest smoke
- staging: full package build, 323 CTest entries, regtest smoke, bench sanity,
  fuzz smoke
- release-manifest: release package build, 322 CTest entries, manifest

Heavy sanitizer jobs evaluated successfully through `nix flake check
--no-build --all-systems`, but were not built locally during initial setup.

## Known Limitations

- The top-level flake currently exposes one default adapter directly. Because
  nothing is deployed yet, prefer a clean breaking refactor to `lib.mkProject`
  and `lib.projectAdapters` before publishing production jobsets.
- Saugus does not exist yet. Create it as the first consumer deployment before
  adding production Hydra host config, lock branches, cache signing config, or
  benchmark worker inventory.
- ASan/UBSan and TSan are implemented as staging/Hydra jobs but need Hydra
  builder capacity before they should gate promotion.
- MSan is build-only until instrumented dependencies are packaged.
- IBD replay, previous-release compatibility, long fuzz budgets, and pinned
  fuzz corpora are documented as future staging/release work.
- The source-repo workflow in `examples/source-correctness.yml` is a template;
  wire it into the source repository once the Ironworks remote exists.
- Ironworks has no remote-specific cache configured yet. Add Cachix or Hydra
  cache details once the hosting/cache names are chosen.

## Next Changes To Prefer

Prefer this order:

- refactor the Ironworks flake around the public library API
- add library/API checks and at least one fixture consumer
- add reusable NixOS modules for Hydra, builders, benchmark workers, and
  self-hosted runners
- create `2140-dev/ironworks` and `2140-dev/saugus`
- scaffold Saugus as the first deployment consumer
- wire `examples/source-correctness.yml` into the source repository
- stand up Hydra jobsets from Saugus lock branches using
  `hydraJobs.${system}.{correctness,staging,release}`
- add a cache and make CI use it
- add the next project adapter only after hosted correctness works for the
  current default adapter
- add real staging fixtures one at a time: pinned fuzz corpus, previous-release
  compatibility, deterministic IBD replay
