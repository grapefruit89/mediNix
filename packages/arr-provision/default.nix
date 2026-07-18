# ---
# meta:
#   role: package
#   purpose: arr-provision — Python CLIs for declarative *arr / Seerr API sync
#   tags:
#     - media
#     - arr
#     - provisioning
# ---
{
  lib,
  python3,
  stdenv,
}:

let
  arrRoot = lib.cleanSource ./.;

  mkCli =
    name: module:
    stdenv.mkDerivation {
      pname = name;
      version = "1.0.0";
      dontUnpack = true;
      installPhase = ''
          mkdir -p "$out/bin"
          cat > "$out/bin/${name}" <<EOF
        #!${stdenv.shell}
        export PYTHONPATH="${arrRoot}:$PYTHONPATH"
        exec ${python3}/bin/python3 -c "from arr_provision.${module} import main; main()"
        EOF
          chmod +x "$out/bin/${name}"
      '';
    };

  downloadClients = mkCli "arr-sync-download-clients" "download_clients";
  prowlarrSync = mkCli "arr-sync-prowlarr" "prowlarr_sync";
  localeSync = mkCli "arr-sync-locale" "locale_sync";
  seerrSync = mkCli "arr-sync-seerr" "seerr_sync";
  arrSettingsSync = mkCli "arr-sync-settings" "arr_settings_sync";
  arrKeysSync = mkCli "arr-sync-keys" "arr_keys_sync";
  jellyfinSetup = mkCli "arr-sync-jellyfin" "jellyfin_setup";
  profileSync = mkCli "arr-sync-profiles" "profile_sync";

  testRunner = stdenv.mkDerivation {
    pname = "arr-provision-tests";
    version = "1.0.0";
    src = arrRoot;
    nativeBuildInputs = [ python3 ];
    dontConfigure = true;
    installPhase = ''
      export PYTHONPATH="${arrRoot}:$PYTHONPATH"
      ${python3}/bin/python3 -m unittest discover -s ${arrRoot}/tests -q
      mkdir -p "$out"
      touch "$out/pass"
    '';
  };
in
stdenv.mkDerivation {
  pname = "arr-provision";
  version = "1.0.0";
  dontUnpack = true;

  installPhase = ''
    mkdir -p "$out/bin"
    cp -L ${downloadClients}/bin/arr-sync-download-clients "$out/bin/"
    cp -L ${prowlarrSync}/bin/arr-sync-prowlarr "$out/bin/"
    cp -L ${localeSync}/bin/arr-sync-locale "$out/bin/"
    cp -L ${seerrSync}/bin/arr-sync-seerr "$out/bin/"
    cp -L ${arrSettingsSync}/bin/arr-sync-settings "$out/bin/"
    cp -L ${arrKeysSync}/bin/arr-sync-keys "$out/bin/"
    cp -L ${jellyfinSetup}/bin/arr-sync-jellyfin "$out/bin/"
    cp -L ${profileSync}/bin/arr-sync-profiles "$out/bin/"
  '';

  passthru = {
    inherit
      downloadClients
      prowlarrSync
      localeSync
      seerrSync
      arrSettingsSync
      arrKeysSync
      jellyfinSetup
      profileSync
      ;
    tests = testRunner;
  };

  meta = {
    description = "Declarative API provisioning for the q958 media stack";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
