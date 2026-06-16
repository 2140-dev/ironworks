{
  runCommand,
  nodePackage,
}:

runCommand "2140-node-bench-sanity" { } ''
  set -euo pipefail

  if [ ! -x "${nodePackage}/libexec/bench_bitcoin" ]; then
    echo "bench_bitcoin was not installed by ${nodePackage}" >&2
    exit 1
  fi

  ${nodePackage}/libexec/bench_bitcoin -sanity-check
  touch "$out"
''
