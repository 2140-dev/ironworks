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
      if [ -x "${nodePackage}/bin/$candidate" ]; then
        ln -s "${nodePackage}/bin/$candidate" "$out/bin/$candidate"
        linked=$((linked + 1))
      fi
    done

    test -x "${nodePackage}/bin/bitcoind"

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
