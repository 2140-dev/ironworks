# CI Parity

This inventory tracks the old source CI matrix against the Ironworks stage
model. A job is not considered ported until it has a concrete Nix output and an
owner decision about whether it gates `forge` or runs as observation-only
coverage.

## Current Policy

- `spark` stays small: formatting, fast source lint, Linux package/unit build,
  and installed regtest smoke.
- `forge` carries staging integration coverage from Hydra.
- `harden` carries expensive scheduled work: long fuzzing, IBD, compatibility,
  and benchmark artifacts.
- Analysis and cross-platform jobs start as non-gating until runtime and
  flakiness are known from real Hydra builders.

## Matrix

| Old CI job | Target stage | Current Ironworks output | Status | Gate policy |
| --- | --- | --- | --- | --- |
| `lint` | `spark` | `checks.${system}.correctness-lint` | Partial | Required in Spark |
| Linux unit/package | `spark` | `checks.${system}.correctness-linux-unit` | Ported | Required in Spark |
| Regtest smoke | `spark` | `checks.${system}.correctness-regtest-smoke` | Ported | Required in Spark |
| `test ancestor commits` | `spark` or `forge` | Missing | Planned | Non-gating until runtime is known |
| macOS native | `forge` | `packages.aarch64-darwin.*` evaluates in Ironworks | Partial | Requires Darwin builder before gating |
| macOS native fuzz | `harden` | Missing | Planned | Scheduled only |
| iwyu | `forge` analysis | `hydraJobs.${system}.staging.analysis.iwyu-report` | Ported | Non-gating report first |
| 32-bit ARM cross | `forge` platform | `hydraJobs.${system}.staging.platforms.armv7` | Ported | Non-gating first |
| macOS cross arm64 | `forge` | Reserved under `hydraJobs.${system}.staging.platforms` | Missing | Non-gating first |
| macOS cross x86_64 | `forge` | Reserved under `hydraJobs.${system}.staging.platforms` | Missing | Non-gating first |
| FreeBSD cross | `forge` | Reserved under `hydraJobs.${system}.staging.platforms` | Missing | Non-gating first |
| i686 | `forge` platform | `hydraJobs.${system}.staging.platforms.i686` | Ported | Non-gating first |
| `fuzzer,address,undefined,integer` | `forge`/`harden` | `checks.${system}.staging-fuzz-smoke`, `hydraJobs.${system}.staging.fuzz.targets-report`, `hydraJobs.${system}.staging.fuzz.valgrind-smoke`, `checks.${system}.staging-asan-ubsan`, `hydraJobs.${system}.scheduled.fuzz-corpus` | Forge ported; harden partial | Fast smoke required; ASan/UBSan green locally; reports non-gating; real corpus storage still needed |
| previous releases | `harden` | `hydraJobs.${system}.scheduled.previous-releases` | Scaffold | Scheduled fixture metadata exists; real datadir fixtures still needed |
| Alpine/musl | `forge` platform | `hydraJobs.${system}.staging.platforms.musl` | Ported | Non-gating first |
| tidy | `forge` analysis | `hydraJobs.${system}.staging.analysis.clang-tidy-report` | Ported | Non-gating report first |
| TSan | `forge` heavy | `hydraJobs.${system}.staging.heavy.tsan` | Ported; green locally | Non-gating until stable on Hydra |
| MSan fuzz | `harden` | Planned under `hydraJobs.${system}.scheduled.fuzz-corpus` | Planned | Scheduled only after instrumented dependencies exist |
| MSan | `forge` heavy | `hydraJobs.${system}.staging.heavy.msan-build` | Ported build-only; green locally | Build-only until instrumented deps exist |

## Hydra Groups

Current `forge` output groups:

```text
hydraJobs.${system}.staging.required
hydraJobs.${system}.staging.full
hydraJobs.${system}.staging.regtest-smoke
hydraJobs.${system}.staging.bench-sanity
hydraJobs.${system}.staging.fuzz-smoke
hydraJobs.${system}.staging.fuzz.*
hydraJobs.${system}.staging.heavy.*
hydraJobs.${system}.staging.platforms.*
hydraJobs.${system}.staging.analysis.*
```

`platforms`, `analysis`, `fuzz`, and `heavy` contain concrete non-gating
derivations. The Linux platform jobs use native Cap'n Proto/mpgen code
generation for cross builds, and the current i686/musl/aarch64/armv7 jobs build
locally on x86_64-linux. They are published for observation first so builder
runtime and flakiness can be measured before any of them are promoted into
`staging.required`.

Current scheduled `harden` outputs:

```text
hydraJobs.${system}.scheduled.required
hydraJobs.${system}.scheduled.ibd-small
hydraJobs.${system}.scheduled.previous-releases
hydraJobs.${system}.scheduled.fuzz-corpus
hydraJobs.${system}.scheduled.benchmark-artifact
hydraJobs.${system}.scheduled.benchmark-report
```

The IBD, previous-release, and fuzz-corpus jobs currently validate pinned
metadata and emit scaffold reports. They should not be treated as production
coverage until fixture storage and schedules are approved.

## Will Clark CI Audit

Will Clark's `bitcoin-core-ci` work is a NixOS queue-runner setup rather than a
Hydra jobset port. The useful pieces were translated into Ironworks as pure Nix
outputs:

- valgrind fuzzing maps to `hydraJobs.${system}.staging.fuzz.valgrind-smoke`
- fuzz target discovery maps to `hydraJobs.${system}.staging.fuzz.targets-report`
- benchmark execution maps to `hydraJobs.${system}.scheduled.benchmark-report`
- benchmark worker consumption remains `hydraJobs.${system}.scheduled.benchmark-artifact`

The queue runner, mutable checkout state, CDash submission, and local dashboard
state are intentionally not imported into Ironworks.

## Remaining Porting Order

1. Add or explicitly reject `test ancestor commits` after measuring runtime.
2. Tighten `checks.${system}.correctness-lint` against the source `ci/lint.py`
   inventory.
3. Add macOS cross jobs after confirming the depends/toolchain inputs.
4. Add FreeBSD cross after choosing the supported cross toolchain path.
5. Add native Darwin only when a Darwin builder exists.
6. Replace the current `harden` metadata scaffolds with real fixture-backed
   IBD, previous-release compatibility, and long fuzzing jobs.
7. Replace MSan build-only with runnable MSan once instrumented dependencies
   are packaged.

## Local Validation Snapshot

The Forge parity fixes were validated locally on x86_64-linux with:

```sh
nix fmt
nix flake check --no-build --all-systems --print-build-logs --accept-flake-config --option eval-cache false
nix build .#checks.x86_64-linux.staging-platform-i686 .#checks.x86_64-linux.staging-platform-musl .#checks.x86_64-linux.staging-platform-aarch64 .#checks.x86_64-linux.staging-platform-armv7 --no-link --print-build-logs --accept-flake-config --option eval-cache false --keep-going
nix build .#checks.x86_64-linux.staging-asan-ubsan --no-link --print-build-logs --accept-flake-config --option eval-cache false
nix build .#checks.x86_64-linux.staging-tsan --no-link --print-build-logs --accept-flake-config --option eval-cache false
nix build .#checks.x86_64-linux.staging-msan-build --no-link --print-build-logs --accept-flake-config --option eval-cache false
```

Results:

- i686, musl, aarch64, and armv7 platform builds succeeded locally.
- ASan/UBSan and TSan each completed 322 CTest entries with zero failures and
  the existing upstream `script_assets_tests` skip.
- MSan completed the full build-only target and intentionally skipped runtime
  tests pending instrumented dependencies.
