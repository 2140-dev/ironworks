{ runCommand, lib }:

name: drvs:
runCommand name { } ''
  ${lib.concatMapStringsSep "\n" (drv: "test -e ${drv}") drvs}
  touch "$out"
''
