# Ironworks

External Nix packaging, CI, Hydra, release, and benchmark infrastructure for
Bitcoin node projects.

The source repository owns CMake targets, options, tests, and install rules.
This repository owns dependency pins, project adapters, package profiles, CI
stages, Hydra jobsets, binary cache policy, and release artifact composition.

The current default adapter is `projects/2140-node`, which targets the
`2140-dev/bitcoin` source tree. The stage model is intended to support other
implementations, such as Bitcoin Core, btcd, and libbitcoin, by adding new
project adapters.

Target remote:

```text
2140-dev/ironworks
```

## Local Correctness

Run the same correctness stage intended for PR CI against a local checkout:

```sh
nix run .#run-correctness -- /home/josie/2140-node
```

Equivalent direct command:

```sh
nix build .#checks.x86_64-linux.correctness \
  --override-input node path:/home/josie/2140-node \
  --print-build-logs
```

## Stages

Human-facing stage names:

- `spark`: fast, local-reproducible PR correctness gate.
- `forge`: integration checks for accepted changes interacting with each other.
- `harden`: scheduled heavy validation such as IBD, fuzz corpus, and long
  benchmarks.
- `temper`: release candidate validation.
- `stamp`: final tag, manifest, and artifact publication.

The current Nix attrs intentionally remain literal for automation:
`correctness`, `staging`, `scheduled`, and `release`.

Consumers can enable or disable canonical stages with:

```nix
ironworks.lib.mkStageConfig {
  enable = [ "harden" ];
  disable = [ "stamp" ];
}
```

Hydra can evaluate the same surface:

```sh
nix eval .#hydraJobs.x86_64-linux --apply builtins.attrNames
nix flake check --no-build --all-systems
```

The detailed workflow is documented in [docs/workflow.md](docs/workflow.md).
Project adapter structure is documented in
[docs/project-adapters.md](docs/project-adapters.md).
Design context and handoff notes are in
[docs/design-notes.md](docs/design-notes.md).
The production rollout architecture is in
[docs/production-architecture.md](docs/production-architecture.md).
The step-by-step production buildout plan is in
[docs/production-buildout-plan.md](docs/production-buildout-plan.md).
