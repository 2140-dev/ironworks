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
| iwyu | `forge` or `harden` | Reserved under `hydraJobs.${system}.staging.analysis` | Missing | Non-gating first |
| 32-bit ARM cross | `forge` | Reserved under `hydraJobs.${system}.staging.platforms` | Missing | Non-gating first |
| macOS cross arm64 | `forge` | Reserved under `hydraJobs.${system}.staging.platforms` | Missing | Non-gating first |
| macOS cross x86_64 | `forge` | Reserved under `hydraJobs.${system}.staging.platforms` | Missing | Non-gating first |
| FreeBSD cross | `forge` | Reserved under `hydraJobs.${system}.staging.platforms` | Missing | Non-gating first |
| i686 | `forge` | Reserved under `hydraJobs.${system}.staging.platforms` | Missing | Non-gating first |
| `fuzzer,address,undefined,integer` | `harden` | `checks.${system}.staging-fuzz-smoke`, `checks.${system}.staging-asan-ubsan`, `hydraJobs.${system}.scheduled.fuzz-corpus` | Scaffold | Scheduled corpus metadata exists; real corpus storage still needed |
| previous releases | `harden` | `hydraJobs.${system}.scheduled.previous-releases` | Scaffold | Scheduled fixture metadata exists; real datadir fixtures still needed |
| Alpine/musl | `forge` | Reserved under `hydraJobs.${system}.staging.platforms` | Missing | Non-gating first |
| tidy | `forge` or `harden` | Reserved under `hydraJobs.${system}.staging.analysis` | Missing | Non-gating first |
| TSan | `forge` heavy | `hydraJobs.${system}.staging.heavy.tsan` | Partial | Non-gating until stable |
| MSan fuzz | `harden` | Planned under `hydraJobs.${system}.scheduled.fuzz-corpus` | Planned | Scheduled only after instrumented dependencies exist |
| MSan | `forge` heavy | `hydraJobs.${system}.staging.heavy.msan-build` | Partial | Build-only until instrumented deps exist |

## Hydra Groups

Current `forge` output groups:

```text
hydraJobs.${system}.staging.required
hydraJobs.${system}.staging.full
hydraJobs.${system}.staging.regtest-smoke
hydraJobs.${system}.staging.bench-sanity
hydraJobs.${system}.staging.fuzz-smoke
hydraJobs.${system}.staging.heavy.*
hydraJobs.${system}.staging.platforms.*
hydraJobs.${system}.staging.analysis.*
```

`platforms` and `analysis` are intentionally empty until each job has a real
derivation. This keeps the public Hydra shape stable without pretending planned
coverage is already green.

Current scheduled `harden` outputs:

```text
hydraJobs.${system}.scheduled.required
hydraJobs.${system}.scheduled.ibd-small
hydraJobs.${system}.scheduled.previous-releases
hydraJobs.${system}.scheduled.fuzz-corpus
hydraJobs.${system}.scheduled.benchmark-artifact
```

The IBD, previous-release, and fuzz-corpus jobs currently validate pinned
metadata and emit scaffold reports. They should not be treated as production
coverage until fixture storage and schedules are approved.

## Next Porting Order

1. Add the smallest cross package that can evaluate on Linux without extra
   infrastructure, likely `i686` or `musl`.
2. Add clang-tidy as a report-producing analysis job.
3. Add iwyu as a report-producing analysis job.
4. Add macOS cross jobs after confirming the depends/toolchain inputs.
5. Add native Darwin only when a Darwin builder exists.
6. Replace the current `harden` metadata scaffolds with real fixture-backed
   IBD, previous-release compatibility, and long fuzzing jobs.
