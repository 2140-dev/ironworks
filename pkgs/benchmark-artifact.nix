{
  jq,
  runCommand,
  stdenv,
  nodePackage,
}:

runCommand "2140-node-benchmark-artifact"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    set -euo pipefail

    mkdir -p "$out/bin" "$out/share/ironworks"

    linked=0
    for candidate in bitcoind bitcoin-cli bitcoin-bench bench_bitcoin; do
      for program_dir in bin libexec; do
        if [ -x "${nodePackage}/$program_dir/$candidate" ]; then
          ln -s "${nodePackage}/$program_dir/$candidate" "$out/bin/$candidate"
          linked=$((linked + 1))
          break
        fi
      done
    done

    test -x "${nodePackage}/bin/bitcoind"
    test -x "$out/bin/bench_bitcoin"

    jq -n \
      --arg package "${nodePackage}" \
      --arg system "${stdenv.hostPlatform.system}" \
      --argjson linked "$linked" \
      '{
        schemaVersion: 1,
        project: "2140-node",
        stage: "harden",
        job: "benchmark-artifact",
        package: $package,
        system: $system,
        linkedPrograms: $linked
      }' > "$out/share/ironworks/benchmark-artifact.json"
  ''
