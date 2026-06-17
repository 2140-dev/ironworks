{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  python3,
  jq,
  git,
  boost,
  capnproto,
  libevent,
  openssl,
  sqlite,
  zeromq,
  zlib,
  libsystemtap ? null,
  llvmPackages_latest,
  src,
  maxFiles ? null,
}:

let
  cleanSource = lib.cleanSourceWith {
    src = lib.cleanSource src;
    filter =
      path: type:
      let
        name = baseNameOf path;
      in
      !(type == "directory" && (name == "build" || lib.hasPrefix "cmake-build-" name))
      && name != "CMakeCache.txt";
  };

  maxFilesArg = "--argjson maxFiles ${if maxFiles == null then "0" else toString maxFiles}";
in
stdenv.mkDerivation {
  pname = "2140-node-clang-tidy-report";
  version = "31.99.0-unstable";

  src = cleanSource;

  strictDeps = true;

  nativeBuildInputs = [
    cmake
    git
    jq
    ninja
    pkg-config
    python3
    llvmPackages_latest.clang
    llvmPackages_latest.clang-tools
    llvmPackages_latest.llvm
  ];

  buildInputs = [
    boost
    capnproto
    libevent
    openssl
    sqlite.dev
    llvmPackages_latest.clang-unwrapped.dev
    zeromq
    zlib
  ]
  ++ lib.optionals (libsystemtap != null) [ libsystemtap ];

  dontFixup = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cmake -S contrib/devtools/bitcoin-tidy -B tidy-build -G Ninja \
      -DLLVM_DIR=${llvmPackages_latest.llvm.dev}/lib/cmake/llvm \
      -DCMAKE_BUILD_TYPE=Release
    cmake --build tidy-build --target bitcoin-tidy --parallel "$NIX_BUILD_CORES"

    cmake -S . -B build -G Ninja \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DBUILD_BITCOIN_BIN=ON \
      -DBUILD_DAEMON=ON \
      -DBUILD_CLI=ON \
      -DBUILD_TESTS=ON \
      -DBUILD_BENCH=OFF \
      -DBUILD_FUZZ_BINARY=OFF \
      -DBUILD_FOR_FUZZING=OFF \
      -DBUILD_UTIL_CHAINSTATE=OFF \
      -DBUILD_KERNEL_LIB=OFF \
      -DBUILD_KERNEL_TEST=OFF \
      -DREDUCE_EXPORTS=OFF \
      -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF \
      -DWITH_CCACHE=OFF \
      -DWITH_EMBEDDED_ASMAP=ON \
      -DWITH_USDT=OFF \
      -DWITH_EXTERNAL_LIBMULTIPROCESS=OFF \
      -DINSTALL_MAN=OFF
    cmake --build build --target generate_build_info --parallel "$NIX_BUILD_CORES"

    mkdir -p report
    jq '
      def unsupportedArgs: [
        "-fstack-reuse=none",
        "-fno-extended-identifiers",
        "-Wduplicated-branches",
        "-Wduplicated-cond",
        "-Wlogical-op",
        "-Wbidi-chars=any",
        "-Wleading-whitespace=spaces",
        "-Wtrailing-whitespace=any"
      ];
      map(
        (if has("command") then
          .command |= (reduce unsupportedArgs[] as $arg (. ; gsub(" " + $arg; "")))
        else . end)
        | (if has("arguments") then
          .arguments |= map(select(. as $arg | (unsupportedArgs | index($arg) | not)))
        else . end)
      )
    ' build/compile_commands.json > report/compile_commands.json

    jq -r ${maxFilesArg} '
      ([.[].file | select(test("/src/.*[.](cpp|cxx|cc)$"))] | unique)
      | if ($maxFiles // 0) > 0 then .[:$maxFiles] else . end
      | .[]
    ' report/compile_commands.json > report/files.txt

    mapfile -t cxx_include_dirs < <(
      echo | ${stdenv.cc}/bin/c++ -E -x c++ - -v 2>&1 \
        | sed -n '/#include <...> search starts here:/,/End of search list./p' \
        | sed '1d;$d;s/^ *//'
    )
    clang_tidy_extra_args=(--extra-arg-before=--driver-mode=g++)
    for include_dir in "''${cxx_include_dirs[@]}"; do
      clang_tidy_extra_args+=(--extra-arg=-isystem"$include_dir")
    done

    status=0
    while IFS= read -r file; do
      echo "### clang-tidy $file" >> report/clang-tidy.log
      clang-tidy \
        --load="$PWD/tidy-build/libbitcoin-tidy.so" \
        -p "$PWD/report" \
        -config-file="$PWD/src/.clang-tidy" \
        "''${clang_tidy_extra_args[@]}" \
        "$file" >> report/clang-tidy.log 2>&1 || status=$?
    done < report/files.txt

    jq -n \
      --arg tool "clang-tidy" \
      --argjson status "$status" \
      --argjson files "$(wc -l < report/files.txt)" \
      '{tool: $tool, status: $status, files: $files, gating: false}' \
      > report/status.json

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/ironworks"
    cp -R report "$out/share/ironworks/clang-tidy"
    runHook postInstall
  '';

  meta = {
    description = "Non-gating clang-tidy report for 2140-node";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
