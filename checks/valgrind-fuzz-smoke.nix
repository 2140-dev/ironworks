{
  jq,
  runCommand,
  valgrind,
  nodePackage,
  target ? "addition_overflow",
}:

runCommand "2140-node-valgrind-fuzz-smoke"
  {
    nativeBuildInputs = [
      jq
      valgrind
    ];
  }
  ''
    set -euo pipefail

    fuzz_bin="${nodePackage}/libexec/fuzz"
    if [ ! -x "$fuzz_bin" ]; then
      echo "fuzz binary was not installed by ${nodePackage}" >&2
      exit 1
    fi

    mkdir -p report
    FUZZ=${target} valgrind --quiet --error-exitcode=1 "$fuzz_bin" -runs=1 \
      > report/stdout.log \
      2> report/stderr.log

    jq -n \
      --arg tool "valgrind" \
      --arg target "${target}" \
      '{tool: $tool, fuzzTarget: $target, gating: false}' \
      > report/status.json

    mkdir -p "$out/share/ironworks"
    cp -R report "$out/share/ironworks/valgrind-fuzz-smoke"
  ''
