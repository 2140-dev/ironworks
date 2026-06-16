{
  lib,
  runCommand,
  src,
}:

let
  cleanSource = lib.cleanSourceWith {
    src = lib.cleanSource src;
    filter =
      path: type:
      let
        name = baseNameOf path;
      in
      !(
        type == "directory"
        && (
          name == ".direnv"
          || name == "target"
          || name == "build"
          || lib.hasPrefix "build_" name
          || lib.hasPrefix "cmake-build-" name
        )
      );
  };
in
runCommand "2140-node-fast-source-lint"
  {
    src = cleanSource;
  }
  ''
    set -euo pipefail

    cd "$src"

    failed=0
    while IFS= read -r -d "" file; do
      case "$file" in
        ./.git/*|./build*/*|./cmake-build-*/*|./depends/sources/*)
          continue
          ;;
        ./src/leveldb/*|./src/crc32c/*|./src/secp256k1/*|./src/minisketch/*)
          continue
          ;;
        ./src/ipc/libmultiprocess/*|./src/crypto/ctaes/*)
          continue
          ;;
        ./doc/release-notes/release-notes-*)
          continue
          ;;
        ./depends/patches/*|./contrib/guix/patches/*|./ci/test/*.patch)
          continue
          ;;
        ./src/univalue/test/*.json)
          continue
          ;;
      esac

      if ! grep -Iq . "$file"; then
        continue
      fi

      if grep -n '[[:blank:]]$' "$file"; then
        echo "trailing whitespace: $file" >&2
        failed=1
      fi

      if [ -s "$file" ] && [ "$(tail -c 1 "$file" | wc -l)" -eq 0 ]; then
        echo "missing trailing newline: $file" >&2
        failed=1
      fi
    done < <(find . -type f -print0)

    if [ "$failed" -ne 0 ]; then
      exit 1
    fi

    touch "$out"
  ''
