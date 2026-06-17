{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  python3,
  boost,
  capnproto,
  git,
  libevent,
  openssl,
  sqlite,
  zeromq,
  zlib,
  libsystemtap ? null,
  src,
  pnameSuffix ? "",
  buildBitcoin ? true,
  buildDaemon ? true,
  buildCli ? true,
  buildTests ? true,
  runUnitTests ? buildTests,
  buildBench ? false,
  buildFuzzBinary ? false,
  buildForFuzzing ? false,
  buildUtilChainstate ? false,
  buildKernelLib ? buildUtilChainstate,
  buildKernelTest ? false,
  reduceExports ? false,
  warningsAsErrors ? false,
  withEmbeddedAsmap ? true,
  withUsdt ? false,
  withExternalLibmultiprocess ? false,
  installMan ? true,
  sanitizers ? null,
  extraNativeBuildInputs ? [ ],
  extraBuildInputs ? [ ],
  extraCmakeFlags ? [ ],
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

  pname = "2140-node" + lib.optionalString (pnameSuffix != "") "-${pnameSuffix}";
in
stdenv.mkDerivation {
  inherit pname;
  version = "31.99.0-unstable";

  src = cleanSource;

  strictDeps = true;
  cmakeBuildDir = "build";

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    python3
    capnproto
    git
  ]
  ++ extraNativeBuildInputs;

  buildInputs = [
    boost
    capnproto
    libevent
    openssl
    sqlite.dev
    zeromq
    zlib
  ]
  ++ lib.optionals withUsdt [ libsystemtap ]
  ++ extraBuildInputs;

  hardeningDisable = lib.optionals stdenv.hostPlatform.isDarwin [ "stackclashprotection" ];

  cmakeFlags = [
    (lib.cmakeBool "BUILD_BITCOIN_BIN" buildBitcoin)
    (lib.cmakeBool "BUILD_DAEMON" buildDaemon)
    (lib.cmakeBool "BUILD_CLI" buildCli)
    (lib.cmakeBool "BUILD_TESTS" buildTests)
    (lib.cmakeBool "BUILD_BENCH" buildBench)
    (lib.cmakeBool "BUILD_FUZZ_BINARY" buildFuzzBinary)
    (lib.cmakeBool "BUILD_FOR_FUZZING" buildForFuzzing)
    (lib.cmakeBool "BUILD_UTIL_CHAINSTATE" buildUtilChainstate)
    (lib.cmakeBool "BUILD_KERNEL_LIB" buildKernelLib)
    (lib.cmakeBool "BUILD_KERNEL_TEST" buildKernelTest)
    (lib.cmakeBool "REDUCE_EXPORTS" reduceExports)
    (lib.cmakeBool "CMAKE_COMPILE_WARNING_AS_ERROR" warningsAsErrors)
    (lib.cmakeBool "WITH_CCACHE" false)
    (lib.cmakeBool "WITH_EMBEDDED_ASMAP" withEmbeddedAsmap)
    (lib.cmakeBool "WITH_USDT" withUsdt)
    (lib.cmakeBool "WITH_EXTERNAL_LIBMULTIPROCESS" withExternalLibmultiprocess)
    (lib.cmakeBool "INSTALL_MAN" installMan)
  ]
  ++ lib.optionals (sanitizers != null) [ "-DSANITIZERS=${sanitizers}" ]
  ++ extraCmakeFlags;

  doCheck = runUnitTests;
  checkPhase = ''
    runHook preCheck
    ctest --output-on-failure --parallel "$NIX_BUILD_CORES" --stop-on-failure
    runHook postCheck
  '';

  postInstall = ''
    mkdir -p "$out"

    fuzz_bin=
    for candidate in bin/fuzz "$cmakeBuildDir/bin/fuzz"; do
      if [ -x "$candidate" ]; then
        fuzz_bin="$candidate"
        break
      fi
    done

    if [ -n "$fuzz_bin" ]; then
      install -Dm755 "$fuzz_bin" "$out/libexec/fuzz"
    fi

    pkg_config="$out/lib/pkgconfig/libbitcoinkernel.pc"
    if [ -f "$pkg_config" ]; then
      sed -i -E 's@^(libdir|includedir)=\$\{prefix\}/(/nix/store/.*)$@\1=\2@' "$pkg_config"
    fi
  '';

  meta = {
    description = "2140 Bitcoin node";
    homepage = "https://github.com/2140-dev/bitcoin";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
