{
  runCommand,
  nodePackage,
}:

runCommand "2140-node-fuzz-smoke" { } ''
  set -euo pipefail

  if [ ! -x "${nodePackage}/libexec/fuzz" ]; then
    echo "fuzz binary was not installed by ${nodePackage}" >&2
    exit 1
  fi

  FUZZ=addition_overflow ${nodePackage}/libexec/fuzz -runs=1
  touch "$out"
''
