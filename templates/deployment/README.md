# Ironworks Deployment Template

This template shows how to consume Ironworks from a separate deployment flake.

Replace the source input, project id, hostnames, cache settings, and host
inventory before deploying.

The template enables `spark`, `forge`, and `temper` by default. It disables
`harden` and `stamp` with `ironworks.lib.mkStageConfig`; enable them only after
your adapter has concrete scheduled-validation or publication jobs for those
stages.
