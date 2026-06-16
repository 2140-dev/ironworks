# Project Adapters

Ironworks is the stage framework. Project adapters are the implementation-
specific layer.

The current default adapter is:

```text
projects/2140-node/default.nix
```

It targets the `node` flake input, currently pinned to:

```text
git+https://github.com/2140-dev/bitcoin.git?ref=master
```

## Contract

A project adapter is a Nix function that receives the common Ironworks context:

```nix
{
  pkgs,
  src,
  config,
  treefmtCheck,
  flakeLock,
}
```

It returns:

```nix
{
  packages = { ... };
  checks = { ... };
  hydraJobs = { ... };
}
```

Consumers should normally call `ironworks.lib.mkProject` rather than an adapter
directly. `mkProject` normalizes stage config, supplies common defaults, and
projects the adapter outputs onto the canonical Ironworks stages.

Use `ironworks.lib.mkStageConfig` for consumer stage policy:

```nix
stages = ironworks.lib.mkStageConfig {
  enable = [ "harden" ];
  disable = [ "stamp" ];
};
```

The helper validates stage names and rejects contradictory requests.

The top-level flake still exposes the bundled default adapter's outputs
directly:

```text
packages.${system}
checks.${system}
hydraJobs.${system}
```

This preserves the current CI and Hydra surface while keeping implementation-
specific assumptions out of the top-level flake.

## Stage Mapping

Adapters should map their implementation-specific checks onto the Ironworks
stage vocabulary:

- `spark`: fast PR correctness
- `forge`: staging integration
- `harden`: scheduled heavy validation
- `temper`: release candidate validation
- `stamp`: final release publication

The low-level Nix names can stay literal and script-friendly. The current
adapter exposes `correctness`, `staging`, and `release` checks because those are
stable automation handles.

`mkProject` keeps every canonical stage visible through `stageChecks` and
`stageHydraJobs`. Each stage projection records whether it is:

- `enabled`: requested by the consumer config
- `implemented`: supplied by the adapter
- `active`: both enabled and implemented

Disabled stage handles are removed from the exported canonical `hydraJobs`
attrs, and their member checks are removed from exported `checks`. Missing
stages remain visible as `implemented = false` in the stage projection, so a
deployment can show the whole roadmap without pretending future work is
production-ready.

## Adapter Responsibilities

Each adapter owns:

- source build system and package definitions
- package profiles for correctness, staging, heavy jobs, and release
- implementation-specific smoke tests
- benchmark binary/profile choices
- release artifact shape
- project-specific Hydra job grouping

Examples:

- Bitcoin Core-like CMake node: daemon/CLI package, CTest, regtest smoke,
  fuzz binary, sanitizer builds, bench sanity
- btcd: Go packages, `go test`, btcd CLI smoke, Go race detector, module cache
  policy
- libbitcoin: CMake packages, library/API tests, daemon smoke if applicable,
  release library artifacts

## Current 2140-Node Adapter

The current adapter is Bitcoin-Core-like and assumes:

- CMake options compatible with the 2140 source tree
- binaries named `bitcoind`, `bitcoin-cli`, and `bitcoin`
- CTest-based unit tests
- installed regtest smoke through the node IPC socket
- optional fuzz, bench, sanitizer, chainstate, and kernel profiles

The adapter uses the package implementation in:

```text
pkgs/2140-node.nix
```

The supporting checks live in `checks/`. Some of those checks are currently
Bitcoin-Core-like rather than fully generic, especially `regtest-smoke.nix`,
`bench-sanity.nix`, and `fuzz-smoke.nix`.

Current stage coverage:

| Stage | Attr | Status |
| --- | --- | --- |
| `spark` | `correctness` | Implemented |
| `forge` | `staging` | Implemented |
| `harden` | `scheduled` | Scaffolded |
| `temper` | `release` | Implemented |
| `stamp` | `stamp` | Planned |

The current `harden` outputs validate explicit IBD, previous-release, and fuzz
corpus metadata, and expose a benchmark artifact package. They are not full
production validation until real fixtures, corpora, and schedules are supplied
by the consuming deployment.

## Adding Another Project

Add a new adapter directory:

```text
projects/<project-id>/default.nix
```

Then add a flake input for that source and choose how to expose it:

- replace `mkDefaultProject` if Ironworks should target that project by default
- add prefixed outputs if multiple projects should be evaluated from one flake
- add a separate branch/jobset if Hydra should evaluate one project at a time

For example, a future Bitcoin Core adapter might use:

```text
projects/bitcoin-core/default.nix
pkgs/bitcoin-core.nix
```

A future btcd adapter might use:

```text
projects/btcd/default.nix
pkgs/btcd.nix
```

Prefer adding one adapter at a time and keeping each adapter's first stage small:
package build, unit tests, and one installed smoke test.
