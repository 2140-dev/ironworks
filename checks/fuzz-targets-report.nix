{
  jq,
  runCommand,
  nodePackage,
}:

runCommand "2140-node-fuzz-targets-report"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    set -euo pipefail

    fuzz_bin="${nodePackage}/libexec/fuzz"
    if [ ! -x "$fuzz_bin" ]; then
      echo "fuzz binary was not installed by ${nodePackage}" >&2
      exit 1
    fi

    mkdir -p "$out/share/ironworks/fuzz-targets"
    PRINT_ALL_FUZZ_TARGETS_AND_ABORT=1 "$fuzz_bin" \
      | sort -u > "$out/share/ironworks/fuzz-targets/targets.txt"

    target_count="$(wc -l < "$out/share/ironworks/fuzz-targets/targets.txt")"
    test "$target_count" -gt 0

    jq -n \
      --arg tool "fuzz" \
      --argjson targetCount "$target_count" \
      '{tool: $tool, targetCount: $targetCount, gating: false}' \
      > "$out/share/ironworks/fuzz-targets/status.json"
  ''
