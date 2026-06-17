# Production Buildout Plan

This is the implementation runbook for taking Ironworks from the current local
MVP to the production pipeline described in `docs/production-architecture.md`.
It treats the repository split as part of the bootstrap: Ironworks becomes the
reusable, tested library/framework, and Saugus becomes the first concrete
consumer deployment for the 2140 infrastructure.

The plan is intentionally split by owner:

- `You`: repository, hosting, credentials, hardware, and operational decisions.
- `Codex`: repo changes, Nix expressions, scripts, docs, checks, and local
  verification that can be done from this workspace.

Do the phases in order. Later phases assume earlier acceptance checks are
green.

## Current State

Already implemented in this repo:

- Nix package profiles for correctness, staging, fuzz, sanitizer, and release.
- Default adapter at `projects/2140-node`.
- `checks.${system}.{correctness,staging,release}`.
- `hydraJobs.${system}.{correctness,staging,release}`.
- GitHub Actions workflow for Ironworks itself.
- Source-repository correctness workflow template at
  `examples/source-correctness.yml`.
- Local promotion helper at `apps/promote-to-staging.py`.
- Architecture, workflow, jobset, adapter, and discussion docs.

Current architectural issue:

- The repo is a working tracer bullet, but its flake API still exposes one
  default project directly.
- The docs currently mix reusable Ironworks concepts with 2140 deployment
  concerns such as hostnames, lock branches, cache policy, and Hydra host
  configuration.
- No production deployment consumes Ironworks as a library yet.

Important limitation:

- This is not yet a full conversion of the old source CI matrix.
- Scheduled `harden` jobsets now exist as scaffolds; real fixture/corpus
  storage and schedules are still pending.
- Benchkit orchestration does not exist yet.
- The public Ironworks flake API is not yet stable.
- Hydra hosting, cache keys, branch protection, host inventory, and release
  publishing are not configured yet.
- The `2140-dev/saugus` deployment repo does not exist yet.

## Target Stage Contract

| Stage | Trigger | Required before next stage | Owner of execution |
| --- | --- | --- | --- |
| `spark` | Source PR or Ironworks PR | Fast correctness green | GitHub Actions first, optionally Hydra later |
| `forge` | Reviewed PR promoted to `staging` | Hydra staging required jobs green | Hydra |
| `harden` | Schedule against forge-green staging snapshots | Required heavy validation green | Hydra plus scheduled wrappers |
| `temper` | Release candidate branch | Release jobs green, harden evidence current, benchmarks reviewed | Hydra plus release manager |
| `stamp` | Final release approval | Tag, manifest, artifacts published | Release manager |

Benchmark rule:

- Benchmarks run from forge-green snapshots.
- Benchmark reports are inputs to `temper`.
- Benchmark regressions are not automatic CI blockers.
- Release managers must explicitly review and record accepted benchmark
  regressions before `stamp`.

## Target Repository Boundary

Ironworks and Saugus should be split before the first production deployment.
Nothing is deployed yet, so preserve quality of the public API over short-term
compatibility with the current top-level flake shape.

`2140-dev/ironworks` is the reusable framework:

- common stage vocabulary and stage contracts
- project adapter API
- reusable package/check/jobset builders
- reusable NixOS modules for Hydra controllers, builders, benchmark workers,
  and self-hosted runners
- source workflow templates
- deployment templates
- tests for the library API and the bundled adapters
- no production secrets, host inventory, DNS names, or mutable operational
  state

`2140-dev/saugus` is the 2140 production deployment:

- host inventory and NixOS configurations
- disk layouts, hardware profiles, builder topology, and benchmark worker
  profiles
- Hydra project/jobset definitions and deployment runbooks
- cache signing configuration and encrypted secret metadata
- lock branches for forge/harden/temper that pin source and Ironworks revisions
- 2140-specific policy for staging, releases, benchmark baselines, artifact
  retention, and access control

The source repository remains separate and owns implementation code, CMake
targets, tests, install rules, PR branches, `staging`, and `release/*`.

## Target Ironworks Flake API

Ironworks should be consumable by another flake without copying internal files.
The first consumer is Saugus, but the API should be designed for other orgs to
deploy their own infrastructure.

Stable public outputs:

```text
lib.stages
lib.stageNames
lib.mkProject
lib.mkStageConfig
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
checks.${system}.library-api
checks.${system}.adapter-2140-node
```

Consumer pattern:

```nix
{
  inputs.ironworks.url = "github:2140-dev/ironworks";
  inputs.node.url = "git+https://github.com/2140-dev/bitcoin.git?rev=<sha>";
  inputs.node.flake = false;

  outputs = { self, nixpkgs, ironworks, node, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      project = ironworks.lib.mkProject {
        inherit pkgs;
        adapter = ironworks.lib.projectAdapters."2140-node";
        src = node;
        config = {
          projectId = "2140-node";
          stages = ironworks.lib.mkStageConfig {
            enable = [ "harden" ];
            disable = [ "stamp" ];
          };
        };
      };
    in {
      hydraJobs.${system} = project.hydraJobs;
      checks.${system} = project.checks;
      packages.${system} = project.packages;
    };
}
```

API rules:

- Ironworks owns the canonical stage catalog: `spark`, `forge`, `harden`,
  `temper`, and `stamp`.
- Project adapters own concrete implementations for each stage. They may
  implement only a subset at first; missing stages must be explicit in the
  library projection rather than hidden.
- `lib.mkProject` applies consumer stage enablement. A stage is only exported
  as an active `checks` or `hydraJobs` handle when it is both enabled by config
  and implemented by the adapter.
- `lib.mkStageConfig` is the preferred consumer helper for stage policy. It
  validates stage names and rejects contradictory enable/disable requests.
- Ironworks must not require a hard-coded source input named `node`.
- Ironworks must not require Saugus hostnames, cache names, secrets, or branch
  names.
- Project adapters should accept structured `config` for stage policy,
  package overrides, smoke-test settings, benchmark profiles, and release
  artifact shape.
- Consumers should be able to overlay packages and override stage membership
  without patching Ironworks internals.
- `checks.${system}.library-api` should evaluate at least one synthetic
  consumer flake or fixture that exercises `mkProject`, modules, overlays, and
  templates.

## Phase 0: Split Library And Deployment

Goal: Ironworks has a clean public flake API, and Saugus is ready to become the
first consumer without carrying reusable framework logic.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 0.1 | Codex | Refactor the flake around `lib.mkProject`, `lib.projectAdapters`, `nixosModules`, `templates`, and `overlays`. | A fixture consumer can import Ironworks and expose checks/packages/hydraJobs without relying on the top-level default adapter. |
| 0.2 | Codex | Keep the current 2140 adapter as the first bundled adapter, but remove hard-coded source input assumptions from the public API. | `lib.projectAdapters."2140-node"` accepts an explicit `src` from the consumer. |
| 0.3 | Codex | Add library API checks. | `nix flake check --no-build --all-systems --print-build-logs` includes library/API fixture evaluation. |
| 0.4 | Codex | Add reusable NixOS modules for Hydra controller, Hydra builder, benchmark worker, and self-hosted runner roles. | Modules evaluate with example settings and do not contain 2140-specific hostnames or secrets. |
| 0.5 | Codex | Add a deployment template that shows how another org consumes Ironworks. | `nix flake init -t github:2140-dev/ironworks#deployment` produces a usable skeleton after replacing placeholders. |
| 0.6 | Codex | Move 2140-specific deployment concerns out of Ironworks docs into Saugus-oriented sections or templates. | Ironworks docs distinguish library API from the Saugus deployment. |

Acceptance:

```sh
cd /home/josie/2140-node-packaging
nix flake check --no-build --all-systems --print-build-logs
nix eval .#lib.projectAdapters --apply builtins.attrNames
nix eval .#nixosModules --apply builtins.attrNames
nix eval .#templates --apply builtins.attrNames
```

## Phase 1: Publish Ironworks And Saugus

Goal: the reusable Ironworks framework and the 2140 Saugus deployment both
exist at their agreed production locations.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 1.1 | You | Create the GitHub repository `2140-dev/ironworks`. | Empty repo exists and you can push to it. |
| 1.2 | You | Create the GitHub repository `2140-dev/saugus`. | Empty repo exists and you can push to it. |
| 1.3 | You | Decide whether default branches are `master` or `main`. Current local branch is `master`. | Branch name decision recorded in both repo settings. |
| 1.4 | Codex | Add the production remote and push Ironworks. | `git remote -v` shows `2140-dev/ironworks`; GitHub shows all framework files. |
| 1.5 | Codex | Scaffold Saugus as a consumer of Ironworks. | Saugus flake inputs include `github:2140-dev/ironworks`; local evaluation can expose 2140 hydraJobs. |
| 1.6 | You | Enable branch protection for both default branches after bootstrap. | Direct pushes can be restricted after initial publication. |
| 1.7 | Codex | Open bootstrap PRs if branch protection is enabled before first push. | PRs contain the initial Ironworks and Saugus states. |

Commands:

```sh
cd /home/josie/2140-node-packaging
git remote add origin git@github.com:2140-dev/ironworks.git
git push -u origin master
```

If the remote default branch is `main`:

```sh
cd /home/josie/2140-node-packaging
git branch -m master main
git remote add origin git@github.com:2140-dev/ironworks.git
git push -u origin main
```

Acceptance:

```sh
cd /home/josie/2140-node-packaging
git status --short --branch
nix flake check --no-build --all-systems --print-build-logs
```

Saugus acceptance:

```sh
cd /home/josie/saugus
nix flake check --no-build --all-systems --print-build-logs
nix eval .#hydraJobs.x86_64-linux --apply builtins.attrNames
```

## Phase 2: Hosted Spark

Goal: source PRs are gated by the same Ironworks correctness check developers
can run locally.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 2.1 | Codex | Copy `examples/source-correctness.yml` into `/home/josie/2140-node/.github/workflows/ironworks-spark.yml`. | Source repo has an Ironworks Spark workflow. |
| 2.2 | Codex | Update the source workflow branch/repository reference if the Ironworks default branch is not `master`. | Workflow checks out the correct Ironworks ref. |
| 2.3 | You | Push the source workflow in a source PR. | GitHub Actions starts `Ironworks Spark`. |
| 2.4 | You | Add required status check `Spark` to source branch protection. | Source PR merge is blocked unless Spark is green. |
| 2.5 | Codex | Document the local reproduction command in the source repo if desired. | PR failure can be reproduced locally with one command. |

Required command for local reproduction:

```sh
cd /home/josie/2140-node-packaging
nix build .#checks.x86_64-linux.correctness \
  --override-input node path:/home/josie/2140-node \
  --print-build-logs
```

Acceptance:

- A clean hosted GitHub runner builds `checks.x86_64-linux.correctness`.
- A source PR cannot merge when the Spark job fails.
- Developers can run the same check locally with `nix run
  github:2140-dev/ironworks#run-correctness -- /path/to/2140-node`.

## Phase 3: CI Parity Inventory

Goal: every job from the old source CI is either ported to Ironworks, assigned
to a scheduled stage, or explicitly dropped with a reason.

| Old CI job | Target Ironworks stage | Current status | Required next work |
| --- | --- | --- | --- |
| `lint` | `spark` | Partially covered by `checks.correctness-lint`. | Compare `checks/fast-lint.nix` against `ci/lint.py`; add missing high-signal linters. |
| Linux unit/package | `spark` | Covered by `checks.correctness-linux-unit`. | Keep in Spark. |
| Regtest smoke | `spark` | Covered by `checks.correctness-regtest-smoke`. | Keep in Spark. |
| `test ancestor commits` | `spark` or `forge` | Missing. | Add a separate non-default PR job or Hydra job; do not put it in required Spark until runtime is known. |
| macOS native | `forge` | Darwin package/check outputs evaluate. | Run on an `aarch64-darwin` builder before gating. |
| macOS native fuzz | `harden` | Missing. | Add Darwin fuzz build/check if Darwin fuzzing remains supported. |
| iwyu | `forge` or scheduled `harden` | Report job exists at `staging.analysis.iwyu-report`. | Keep non-gating until report quality is reviewed. |
| 32-bit ARM cross | `forge` | Ported as `staging.platforms.armv7`; green locally. | Observe on Hydra before gating. |
| macOS cross arm64 | `forge` | Missing. | Add Darwin cross package profile and Hydra job. |
| macOS cross x86_64 | `forge` | Missing. | Add Darwin x86_64 cross package profile and Hydra job. |
| FreeBSD cross | `forge` | Missing. | Add FreeBSD cross package profile and Hydra job. |
| i686 | `forge` | Ported as `staging.platforms.i686`; green locally. | Observe on Hydra before gating. |
| `fuzzer,address,undefined,integer` | `forge`/`harden` | Forge coverage exists through `staging.fuzz-smoke`, `staging.fuzz.targets-report`, `staging.fuzz.valgrind-smoke`, and locally green `staging.heavy.asan-ubsan`; `scheduled.fuzz-corpus` remains metadata-only. | Add real corpus/budget scheduling for harden. |
| previous releases | `harden` | Metadata scaffold at `scheduled.previous-releases`. | Add previous-release fixture/package job and scheduled report. |
| Alpine/musl | `forge` | Ported as `staging.platforms.musl`; green locally. | Observe on Hydra before gating. |
| tidy | `forge` or scheduled `harden` | Report job exists at `staging.analysis.clang-tidy-report`. | Keep non-gating until report quality is reviewed. |
| TSan | `forge` heavy | Ported as `staging.heavy.tsan`; green locally. | Build on Hydra, then decide gating after stability. |
| MSan fuzz | `harden` | Planned under the `scheduled.fuzz-corpus` scaffold. | Add instrumented fuzz MSan job if dependencies can be packaged. |
| MSan | `forge` heavy | Build-only covered by `staging.heavy.msan-build`; green locally. | Package instrumented deps before making runtime-gating. |

Tasks:

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 3.1 | Codex | Create `docs/ci-parity.md` from this table and keep it updated. | Every old CI job has a target stage and status. |
| 3.2 | Codex | Add missing `hydraJobs.${system}.staging.platforms.*` outputs for cross/platform jobs one at a time. | `nix eval .#hydraJobs.x86_64-linux.staging.platforms --apply builtins.attrNames` works. |
| 3.3 | Codex | Add missing `hydraJobs.${system}.staging.analysis.*` outputs for iwyu/tidy. | Jobs evaluate and are documented as gating or non-gating. |
| 3.4 | Codex | Add missing `hydraJobs.${system}.scheduled.*` outputs for harden jobs. | `nix eval .#hydraJobs.x86_64-linux.scheduled --apply builtins.attrNames` works. |
| 3.5 | You | Decide which old CI jobs are required for `forge` gating and which are scheduled only. | `docs/ci-parity.md` has final gating decisions. |

Acceptance:

```sh
cd /home/josie/2140-node-packaging
nix eval .#hydraJobs.x86_64-linux --apply builtins.attrNames
nix eval .#hydraJobs.x86_64-linux.staging --apply builtins.attrNames
nix eval .#hydraJobs.x86_64-linux.release --apply builtins.attrNames
nix flake check --no-build --all-systems --print-build-logs
```

## Phase 4: Hydra Host

Goal: Hydra evaluates Saugus jobsets, built from Ironworks' reusable project
API, for protected refs and publishes trusted build outputs.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 4.1 | You | Provision one NixOS host for Hydra. Minimum starting point: 8 vCPU, 32 GB RAM, 500 GB SSD. | Host is reachable over SSH. |
| 4.2 | You | Choose public hostname, for example `hydra.2140.dev`. | DNS A/AAAA record points at the host. |
| 4.3 | You | Decide whether builders are local-only first or separate worker machines. | Builder topology documented in `docs/production-architecture.md`. |
| 4.4 | Codex | Add Saugus `hosts/hydra` using Ironworks' reusable Hydra controller module. | `nixos-rebuild dry-build --flake .#hydra` works from Saugus or on the host. |
| 4.5 | You | Deploy the Hydra host config. | Hydra UI loads over HTTPS. |
| 4.6 | You | Create a Hydra admin user. | You can log into the Hydra UI. |
| 4.7 | Codex | Add Saugus `docs/hydra-jobsets.md` with exact UI field values for the Saugus jobsets. | Jobsets can be created without guessing. |
| 4.8 | You | Create Hydra project `ironworks`. | Project exists in Hydra UI. |
| 4.9 | You | Create jobsets for `spark`, `forge`, `harden`, and `temper`. | Hydra evaluates each jobset at least once. |

Saugus should instantiate the reusable Ironworks Hydra controller module into a
host configuration with this initial shape:

```nix
{ config, pkgs, ... }:

{
  services.hydra = {
    enable = true;
    hydraURL = "https://hydra.2140.dev";
    notificationSender = "hydra@2140.dev";
    useSubstitutes = true;
    port = 3000;
  };

  services.postgresql.enable = true;

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts."hydra.2140.dev" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3000";
    };
  };

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "ops@2140.dev";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "hydra" ];
    builders-use-substitutes = true;
  };
}
```

Initial Hydra jobsets:

| Jobset | Input ref | Flake output | Scheduling |
| --- | --- | --- | --- |
| `spark` | Saugus default branch or source PR workflow | `hydraJobs.x86_64-linux.correctness` | Every Saugus/Ironworks integration commit if used in Hydra |
| `forge` | Saugus `staging-lock` branch | `hydraJobs.x86_64-linux.staging` | Every promoted staging snapshot |
| `harden` | Saugus `staging-lock` branch | `hydraJobs.x86_64-linux.scheduled` | Nightly after forge green |
| `temper` | Saugus `release-lock/<version>` branch | `hydraJobs.x86_64-linux.release` | Every release candidate update |

Important: the `forge`, `harden`, and `temper` jobsets should build Saugus
branches whose `flake.lock` pins the exact Ironworks revision, source commit,
and nixpkgs revision. Do not let production jobsets chase mutable source refs
directly.

Acceptance:

- Hydra evaluates `hydraJobs.x86_64-linux.correctness.required`.
- Hydra evaluates `hydraJobs.x86_64-linux.staging.required`.
- Build logs are retained in Hydra.
- Outputs are visible in the binary cache.

## Phase 5: Binary Cache

Goal: GitHub Actions, Hydra, developers, harden jobs, and benchmark workers all
consume signed build outputs.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 5.1 | You | Choose cache provider: Hydra cache, Cachix, or both. | Choice recorded in docs. |
| 5.2 | You | Create signing key or cache credentials. | Secret exists outside git. |
| 5.3 | Codex | Update GitHub workflows with substituter/public key configuration. | Hosted Spark uses the cache. |
| 5.4 | Codex | Add cache setup to Saugus Hydra host config using Ironworks modules where applicable. | Hydra publishes signed outputs. |
| 5.5 | Codex | Add worker/developer cache instructions. | A new machine can use cached Saugus/Ironworks outputs. |

Acceptance:

```sh
nix build github:2140-dev/saugus#checks.x86_64-linux.correctness \
  --print-build-logs
```

Run the command twice on a fresh machine or runner. The second run should reuse
cached outputs instead of rebuilding everything.

## Phase 6: Promotion To Forge

Goal: reviewed PRs move into staging with traceable merge commits and Hydra
forge coverage.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 6.1 | You | Create protected source branch `staging`. | Branch exists in `2140-node`. |
| 6.2 | You | Create GitHub label `ready-for-staging`. | Label exists. |
| 6.3 | You | Decide who can promote to staging. | Maintainer list recorded. |
| 6.4 | Codex | Add docs for promotion command and revert policy. | Maintainers can promote without reading script internals. |
| 6.5 | Codex | Add a Saugus lock-update helper that pins the promoted source SHA and Ironworks revision into Saugus `staging-lock`. | Saugus lock branch records exact source SHA and Ironworks SHA. |
| 6.6 | You | Run one dry-run promotion. | Merge commit message shows PR number, PR head SHA, target branch, UTC timestamp. |
| 6.7 | You | Run one real promotion. | Hydra `forge` jobset evaluates the locked snapshot. |

Promotion command:

```sh
cd /home/josie/2140-node-packaging
nix run .#promote-to-staging -- \
  --repo 2140-dev/bitcoin \
  --pr <PR_NUMBER> \
  --target staging
```

Dry-run first:

```sh
cd /home/josie/2140-node-packaging
nix run .#promote-to-staging -- \
  --repo 2140-dev/bitcoin \
  --pr <PR_NUMBER> \
  --target staging \
  --no-push
```

Acceptance:

- Source `staging` contains a promotion merge commit.
- Saugus `staging-lock` pins the promoted source SHA and Ironworks revision.
- Hydra `forge` evaluates that Saugus lock commit.
- A failed forge run can be traced back to the source PR and source SHA.

## Phase 7: Forge Job Expansion

Goal: forge replaces the broad integration coverage from the old CI for
staging snapshots.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 7.1 | Codex | Publish the locally green `staging.heavy.asan-ubsan` job through Saugus and build it on real builders. | Job is green for one staging snapshot. |
| 7.2 | Codex | Publish the locally green `staging.heavy.tsan` job through Saugus and build it on real builders. | Job is green or has a tracked issue. |
| 7.3 | Codex | Keep `staging.heavy.msan-build` build-only until instrumented dependencies are packaged. | MSan status is explicit in `docs/ci-parity.md`. |
| 7.4 | Codex | Publish the locally green i686, armhf, aarch64, and musl platform jobs through Saugus; add Darwin cross arm64, Darwin cross x86_64, and FreeBSD cross later. | Each supported job evaluates; Linux platform jobs build in Hydra. |
| 7.5 | Codex | Add native Darwin job output for `aarch64-darwin`. | Runs on a Darwin builder, or is marked blocked on hardware. |
| 7.6 | Codex | Add iwyu and clang-tidy jobs as non-gating analysis first. | Jobs produce reports and do not block staging initially. |
| 7.7 | You | Decide which forge jobs are required gates after observing runtime/flakiness. | Hydra jobset marks required jobs; docs updated. |

Initial forge gating recommendation:

- Required now: `staging.required`.
- Required after one week stable: ASan/UBSan.
- Non-gating until proven stable: TSan, MSan, iwyu, tidy, cross builds.

Acceptance:

- `docs/ci-parity.md` shows no old CI job as unknown.
- Every old CI job is either ported, scheduled, or explicitly rejected.
- Hydra `forge` has enough builder capacity to finish inside the expected
  staging feedback window.

## Phase 8: Scheduled Harden

Goal: expensive validation runs on schedule against forge-green staging
snapshots, not on every staging merge.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 8.1 | Codex | Add `hydraJobs.${system}.scheduled.required` aggregate. | `nix eval .#hydraJobs.x86_64-linux.scheduled.required` works. |
| 8.2 | Codex | Add deterministic IBD fixture metadata format. | Fixture hash, expected height, expected block hash are declared in git. |
| 8.3 | You | Provide or approve storage for IBD fixtures. | Fixture URL/path is reachable by Hydra workers. |
| 8.4 | Codex | Add small deterministic IBD report job. | Report includes source SHA, fixture id, height/hash, duration, logs. |
| 8.5 | Codex | Add previous-release compatibility job. | Report shows upgrade/import result from pinned previous-release datadir. |
| 8.6 | Codex | Add pinned fuzz corpus job with bounded nightly budget. | Report includes corpus hash, target list, duration, failures. |
| 8.7 | You | Decide harden schedule. Initial recommendation: nightly IBD/fuzz/compat, weekly larger IBD. | Schedule recorded in Hydra or scheduler config. |
| 8.8 | Codex | Add issue/notification integration for required harden failures. | Failure opens or updates a staging-health issue. |

Required scheduled outputs:

```text
hydraJobs.x86_64-linux.scheduled.required
hydraJobs.x86_64-linux.scheduled.ibd-small
hydraJobs.x86_64-linux.scheduled.previous-releases
hydraJobs.x86_64-linux.scheduled.fuzz-corpus
hydraJobs.x86_64-linux.scheduled.benchmark-artifact
```

Acceptance:

- `harden` only selects a forge-green snapshot.
- Required harden failures mark staging unhealthy.
- Fixes go through normal PR -> Spark -> promotion -> Forge.
- Harden reports are archived and link to exact source SHA, Ironworks SHA,
  nixpkgs revision, fixture hash, and Nix store path.

## Phase 9: Benchkit Orchestration

Goal: benchmark measurements are reproducible, comparable, and available as
`temper` review input.

Architecture:

```text
forge-green staging snapshot
  -> Hydra builds benchmark artifact
  -> scheduler creates benchmark_run row
  -> dedicated worker leases run
  -> worker downloads exact closure from signed cache
  -> worker symlinks bitcoind into Benchkit bin_dir as bitcoind-<source_sha>
  -> Benchkit runs configured benchmark
  -> worker uploads raw artifacts and normalized summary
  -> comparator creates report against baseline
  -> report is attached to temper/release readiness
```

Data stores:

- SQLite is acceptable for the first single-host MVP.
- PostgreSQL is required before multiple scheduler instances or concurrent
  writers.
- Raw artifacts should be stored outside the database under content-addressed
  paths.

Minimum database tables:

```sql
create table benchmark_runs (
  id text primary key,
  project text not null,
  stage text not null,
  source_sha text not null,
  ironworks_sha text not null,
  nixpkgs_rev text not null,
  store_path text not null,
  benchmark_config_hash text not null,
  worker_profile text not null,
  status text not null,
  requested_at text not null,
  leased_at text,
  completed_at text,
  baseline_run_id text,
  report_path text
);

create table benchmark_samples (
  run_id text not null,
  benchmark_name text not null,
  parameter_key text not null,
  sample_index integer not null,
  duration_ms real not null,
  exit_code integer not null,
  primary key (run_id, benchmark_name, parameter_key, sample_index)
);

create table benchmark_reports (
  run_id text primary key,
  baseline_run_id text,
  status text not null,
  summary_json text not null,
  markdown_path text not null
);
```

Worker contract:

- Worker is not a general Hydra builder.
- Worker has stable CPU governor/frequency settings.
- Worker has fixed benchmark hardware profile id.
- Worker has a local sync node or pinned fixtures.
- Worker trusts only the signed Ironworks/Hydra cache.
- Worker writes raw Benchkit output plus normalized summaries.

Tasks:

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 9.1 | Codex | Add Benchkit as a pinned flake input or package. | `nix build .#packages.x86_64-linux.benchkit` works. |
| 9.2 | Codex | Add benchmark artifact package/profile for `2140-node`. | Hydra builds an output containing `bin/bitcoind` and benchmark metadata. |
| 9.3 | Codex | Add `benchmarks/2140-node/*.yml` Benchkit configs. | Config hash is stable and recorded in run metadata. |
| 9.4 | Codex | Add `apps/bench-scheduler` CLI. | Can enqueue a benchmark run for a source SHA/store path. |
| 9.5 | Codex | Add `apps/bench-worker` CLI. | Can lease one run, execute it, upload artifacts, and mark completion. |
| 9.6 | Codex | Add `apps/bench-compare` CLI. | Produces Markdown and JSON comparison reports against a baseline. |
| 9.7 | You | Provision one dedicated benchmark worker. Initial recommendation: bare metal or pinned VM, 8+ performance cores, 32 GB RAM, NVMe, fixed kernel. | Worker can run `benchkit system check`. |
| 9.8 | You | Decide benchmark storage path or bucket. | Scheduler config has artifact root. |
| 9.9 | You | Decide baseline policy. Initial recommendation: latest stamped release and last green staging run. | Baseline selection documented. |
| 9.10 | Codex | Wire benchmark report into temper docs/checklist. | Release candidate cannot be stamped without report review. |

First manual benchmark smoke:

```sh
# On the benchmark worker
benchkit system check

# Fetch the exact Hydra-built artifact from the Saugus lock branch.
nix build github:2140-dev/saugus/<staging-lock-rev>#packages.x86_64-linux.node-staging-full

# Prepare Benchkit prebuilt binary layout.
mkdir -p /var/lib/ironworks-bench/bin
ln -sf "$(readlink -f result)/bin/bitcoind" \
  /var/lib/ironworks-bench/bin/bitcoind-<source_sha>

# Run Benchkit against the prebuilt binary.
benchkit \
  --app-config /etc/ironworks-bench/config.yml \
  --bench-config /etc/ironworks-bench/benchmark.yml \
  run \
  --out-dir /var/lib/ironworks-bench/runs/<run_id>
```

Acceptance:

- A staging commit can be benchmarked from a Hydra-built cached artifact.
- Results include raw `results.json`, copied configs, system info, logs, and
  normalized samples.
- A report compares the run to the selected baseline.
- The report status can be `pass`, `regression-review-required`, or `failed`.
- `temper` receives the report as input, but the report does not directly set
  required harden health.

## Phase 10: Temper And Stamp

Goal: release branches produce traceable artifacts, and release decisions
consume harden and benchmark evidence.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 10.1 | You | Protect `release/*` branches. | Direct pushes are restricted. |
| 10.2 | Codex | Add Saugus release lock helper for `release-lock/<version>`. | Saugus release lock pins exact source branch, Ironworks revision, and nixpkgs. |
| 10.3 | Codex | Expand release manifest to include source SHA, Ironworks SHA, nixpkgs rev, store paths, checksums, harden report ids, benchmark report id. | Manifest contains all provenance fields. |
| 10.4 | Codex | Add release checklist doc generated from the manifest. | Release manager can review one Markdown file. |
| 10.5 | You | Decide artifact hosting location. | Upload target exists. |
| 10.6 | Codex | Add artifact upload/publish script after hosting decision. | Dry-run publish prints exact artifacts and checksums. |
| 10.7 | You | Perform first dry-run release candidate. | `temper` green, benchmark reviewed, no tag published. |
| 10.8 | You | Approve first `stamp`. | Tag and artifacts are published. |

Release eligibility:

- Source commit is contained in a forge-green staging snapshot, or is a targeted
  release-branch fix that passed release CI.
- Required harden results are recent and green, or were rerun on the release
  branch.
- Benchmark report was reviewed.
- Any accepted benchmark regression is recorded.
- No unresolved staging-blocker issue applies to the release candidate.

Acceptance:

- `hydraJobs.x86_64-linux.release.required` is green.
- Release manifest is complete.
- Benchmark report is attached.
- Final tag can be traced back to source SHA, Ironworks SHA, Hydra builds,
  harden reports, and benchmark report.

## Phase 11: Multi-Project Generalization

Goal: Ironworks can run the same stage model for other node implementations.

Do this only after the 2140-node production path is working.

| ID | Owner | Task | Acceptance check |
| --- | --- | --- | --- |
| 11.1 | You | Pick the next implementation: Bitcoin Core, btcd, or libbitcoin. | Project chosen. |
| 11.2 | Codex | Add `projects/<project-id>/default.nix`. | Adapter exposes `packages`, `checks`, and `hydraJobs`. |
| 11.3 | Codex | Prefix or split flake outputs so multiple projects can coexist. | Hydra can target one project without ambiguity. |
| 11.4 | Codex | Add project-specific source workflow template. | New project can run Spark. |
| 11.5 | You | Decide which stages apply to the new implementation. | Adapter docs record unsupported stages explicitly. |

Acceptance:

- A second project can run Spark and Forge without changing the common stage
  language.
- Project-specific assumptions stay inside `projects/<project-id>`.

## Immediate Next Tasks

Do these next, in this exact order:

| Order | Owner | Task |
| --- | --- | --- |
| 1 | Codex | Refactor Ironworks around `lib.mkProject`, `lib.projectAdapters`, reusable modules, templates, overlays, and library API checks. |
| 2 | You | Create `2140-dev/ironworks` and `2140-dev/saugus`. |
| 3 | Codex | Push Ironworks and scaffold Saugus as the first consumer deployment. |
| 4 | Codex | Install `examples/source-correctness.yml` into the source repo as `ironworks-spark.yml`. |
| 5 | You | Open a test source PR and require Spark in branch protection. |
| 6 | Codex | Add `docs/ci-parity.md` and start porting missing old-CI jobs into explicit Hydra groups. |
| 7 | You | Provision the Hydra host and choose cache provider. |
| 8 | Codex | Add Saugus Hydra host config, jobset docs, and staging/release lock helpers. |
| 9 | You | Create Hydra project/jobsets. |
| 10 | Codex | Add scheduled `harden` outputs, starting with deterministic IBD metadata/report. |
| 11 | You | Provision benchmark worker hardware/storage. |
| 12 | Codex | Add Benchkit package plus scheduler/worker/compare CLIs. |
| 13 | Codex | Wire benchmark reports into `temper` release checklist. |

## Definition Of Done

This plan is complete when all of the following are true:

- Source PRs cannot merge unless `spark` is green.
- Reviewed PRs can be promoted to `staging` with traceable merge commits.
- Ironworks is consumable as a tested library by Saugus and by a fixture
  deployment.
- Hydra builds `forge` from Saugus lock branches that pin exact source SHAs,
  Ironworks SHAs, and nixpkgs revisions.
- Old CI matrix entries are either ported, scheduled, or explicitly rejected.
- Required scheduled `harden` jobs run only after forge-green snapshots.
- Benchmark workers run Benchkit from Hydra-built artifacts and publish reports.
- `temper` consumes required harden health and benchmark reports.
- `stamp` publishes a tag, manifest, and artifacts with full provenance.
