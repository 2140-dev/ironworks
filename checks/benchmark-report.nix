{
  lib,
  jq,
  runCommand,
  nodePackage,
  filter ? "MuHash",
  minTimeMs ? 1,
}:

let
  filterArg = lib.escapeShellArg filter;
in
runCommand "2140-node-benchmark-report"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    set -euo pipefail

    bench_bin="${nodePackage}/libexec/bench_bitcoin"
    if [ ! -x "$bench_bin" ]; then
      bench_bin="${nodePackage}/bin/bench_bitcoin"
    fi
    if [ ! -x "$bench_bin" ]; then
      echo "bench_bitcoin was not installed by ${nodePackage}" >&2
      exit 1
    fi

    mkdir -p report
    "$bench_bin" \
      -filter=${filterArg} \
      -min-time=${toString minTimeMs} \
      -output-json=report/benchmark.json \
      -output-csv=report/benchmark.csv \
      > report/stdout.log \
      2> report/stderr.log

    test -s report/benchmark.json
    result_count="$(
      jq '
        if type == "array" then length
        elif type == "object" and has("results") then (.results | length)
        else 0
        end
      ' report/benchmark.json
    )"
    test "$result_count" -gt 0

    jq -n \
      --arg tool "bench_bitcoin" \
      --arg filter "${filter}" \
      --argjson minTimeMs "${toString minTimeMs}" \
      --argjson resultCount "$result_count" \
      '{tool: $tool, filter: $filter, minTimeMs: $minTimeMs, resultCount: $resultCount, gating: false}' \
      > report/status.json

    mkdir -p "$out/share/ironworks"
    cp -R report "$out/share/ironworks/benchmark-report"
  ''
