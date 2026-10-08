# Infrastructure supplies the exact guest tool store paths. The application
# owns the cleanup policy; this package only pins its interpreter and PATH.
{
  bash,
  coreutils,
  docker,
  python,
  cleanupSource ? ../bin/prod/cleanup,
  system ? builtins.currentSystem,
}:
let
  # Coercing a path directly copies it into another store path. Preserve the
  # existing package identity and dependency context instead.
  bashStore = builtins.storePath bash;
  coreutilsStore = builtins.storePath coreutils;
  dockerStore = builtins.storePath docker;
  pythonStore = builtins.storePath python;
  source = builtins.path {
    path = cleanupSource;
    name = "prosecho-cleanup-source";
  };
in
builtins.derivation {
  name = "prosecho-cleanup";
  inherit system;
  builder = "${bashStore}/bin/bash";
  args = [
    "-c"
    ''
      set -eu
      ${coreutilsStore}/bin/mkdir -p "$out/bin"
      printf '%s\n' \
        '#!${bashStore}/bin/bash' \
        'export PATH=${dockerStore}/bin:${coreutilsStore}/bin:${pythonStore}/bin' \
        'exec ${pythonStore}/bin/python3 ${source} "$@"' \
        > "$out/bin/prosecho-cleanup"
      ${coreutilsStore}/bin/chmod 755 "$out/bin/prosecho-cleanup"
    ''
  ];
}
