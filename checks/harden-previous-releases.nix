{
  jq,
  runCommand,
  fixtureMetadata,
}:

runCommand "2140-node-harden-previous-releases"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    set -euo pipefail

    mkdir -p "$out"

    jq -e '
      has("fixtureId") and
      has("enabled") and
      has("previousReleases") and
      (.previousReleases | type == "array") and
      has("archiveRoot") and
      (.archiveRoot | has("url") and has("sha256"))
    ' ${fixtureMetadata} >/dev/null

    cp ${fixtureMetadata} "$out/fixture.json"

    jq -n \
      --slurpfile fixture ${fixtureMetadata} \
      '{
        stage: "harden",
        job: "previous-releases",
        status: "scaffold",
        reason: "previous-release datadir fixtures are pending",
        fixture: $fixture[0]
      }' > "$out/report.json"
  ''
