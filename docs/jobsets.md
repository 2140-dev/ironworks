# Jobsets

The flake exports stage-oriented jobs through both `checks` and `hydraJobs`.
These are the outputs of the current default project adapter:
`projects/2140-node`.

## Checks

```text
checks.${system}.correctness
checks.${system}.correctness-format
checks.${system}.correctness-lint
checks.${system}.correctness-linux-unit
checks.${system}.correctness-regtest-smoke

checks.${system}.staging
checks.${system}.staging-full
checks.${system}.staging-regtest-smoke
checks.${system}.staging-bench-sanity
checks.${system}.staging-fuzz-smoke
checks.${system}.staging-asan-ubsan
checks.${system}.staging-tsan
checks.${system}.staging-msan-build

checks.${system}.release
checks.${system}.release-package
checks.${system}.release-install-smoke
checks.${system}.release-manifest
checks.${system}.release-checklist

checks.${system}.scheduled
checks.${system}.scheduled-required
checks.${system}.scheduled-ibd-small
checks.${system}.scheduled-previous-releases
checks.${system}.scheduled-fuzz-corpus
checks.${system}.scheduled-benchmark-artifact
```

## Hydra Jobs

```text
hydraJobs.${system}.correctness.required
hydraJobs.${system}.correctness.format
hydraJobs.${system}.correctness.lint
hydraJobs.${system}.correctness.unit
hydraJobs.${system}.correctness.regtest-smoke

hydraJobs.${system}.staging.required
hydraJobs.${system}.staging.full
hydraJobs.${system}.staging.regtest-smoke
hydraJobs.${system}.staging.bench-sanity
hydraJobs.${system}.staging.fuzz-smoke
hydraJobs.${system}.staging.heavy.asan-ubsan
hydraJobs.${system}.staging.heavy.tsan
hydraJobs.${system}.staging.heavy.msan-build

hydraJobs.${system}.release.required
hydraJobs.${system}.release.package
hydraJobs.${system}.release.install-smoke
hydraJobs.${system}.release.manifest
hydraJobs.${system}.release.checklist

hydraJobs.${system}.scheduled.required
hydraJobs.${system}.scheduled.ibd-small
hydraJobs.${system}.scheduled.previous-releases
hydraJobs.${system}.scheduled.fuzz-corpus
hydraJobs.${system}.scheduled.benchmark-artifact
```

Hydra should initially gate on `correctness.required` for PR promotion and
`staging.required` for the integration queue. The `heavy` jobs can be promoted
to gating once they are stable and builder capacity is known. The scheduled
IBD, previous-release, and fuzz-corpus jobs are metadata scaffolds until real
fixture storage and schedules are approved.
