{
  jq,
  runCommand,
  fixtureMetadata,
}:

runCommand "2140-node-harden-ibd-small"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    set -euo pipefail

    mkdir -p "$out"

    jq -e '
      has("fixtureId") and
      has("enabled") and
      has("network") and
      has("height") and
      has("blockHash") and
      has("archive") and
      (.archive | has("url") and has("sha256"))
    ' ${fixtureMetadata} >/dev/null

    cp ${fixtureMetadata} "$out/fixture.json"

    jq -n \
      --slurpfile fixture ${fixtureMetadata} \
      '{
        stage: "harden",
        job: "ibd-small",
        status: "scaffold",
        reason: "fixture storage and scheduled runner policy are pending",
        fixture: $fixture[0]
      }' > "$out/report.json"
  ''
