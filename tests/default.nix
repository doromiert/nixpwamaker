{ pkgs, homeManager }:
let
  inherit (pkgs) lib;
  browser = name: pkgs.runCommand "test-${name}" {} ''
    mkdir -p $out/bin $out/lib/firefox
    cat > $out/bin/${name} <<'SH'
    #!${pkgs.runtimeShell}
    printf '%s\n' "$@" > "$PWA_TEST_ARGS"
SH
    chmod +x $out/bin/${name}
    cp $out/bin/${name} $out/lib/firefox/firefox
  '';
  gnosis = browser "gnosis";
  firefox = browser "firefox";
  testPkgs = pkgs.extend (_: _: { inherit firefox; });
  make = values: homeManager.lib.homeManagerConfiguration {
    pkgs = testPkgs;
    modules = [ ../modules/nixpwamaker.nix {
      home = { username = "tester"; homeDirectory = "/home/tester"; stateVersion = "26.05"; };
      programs.pwamaker = { enable = true; gnosisPackage = gnosis; } // values;
    } ];
  };
  app = { name = "Mail"; url = "https://mail.example/path?q=1%20a&text=$hello`world`"; openUrls = [ "mail.example" ]; };
  only = (make { browser = "gnosis"; apps.mail = app; dispatcher.enable = true; }).config;
  mixed = (make { dispatcher.enable = true; apps = {
    mail = app // { browser = "gnosis"; };
    legacy = app // { id = "legacy"; url = "https://legacy.example/"; openUrls = [ "legacy.example" ]; };
  }; }).config;
  renamed = (make { browser = "gnosis"; apps.mail = app // { name = "Renamed Mail"; }; }).config;
  invalid = values: !(builtins.tryEval (make ({ browser = "gnosis"; apps.mail = app; } // values)).activationPackage.drvPath).success;
  desktopName = "com.neg-zero.Gnosis.WebApp_mail";
  desktop = only.xdg.dataFile."applications/${desktopName}.desktop".source;
  findDispatcher = config: lib.findFirst (p: p.pname or p.name == "pwa-dispatcher") null config.home.packages;
  dispatcher = findDispatcher only;
  mixedDispatcher = findDispatcher mixed;
in
assert only.programs.pwamaker.apps.mail.browser == "gnosis";
assert mixed.programs.pwamaker.apps.legacy.browser == "firefox";
assert mixed.xdg.desktopEntries ? legacy;
assert mixed.xdg.dataFile ? "applications/${desktopName}.desktop";
assert !(only.home.activation ? pwaMakerApply);
assert lib.hasInfix "/legacy" mixed.home.activation.pwaMakerApply.data;
assert !(lib.hasInfix "Configuring PWA: Mail (mail)" mixed.home.activation.pwaMakerApply.data);
assert only.xdg.dataFile."applications/${desktopName}.desktop".target == renamed.xdg.dataFile."applications/${desktopName}.desktop".target;

assert invalid { gnosisPackage = null; };
assert invalid { apps.mail = app // { id = "../escape"; }; };
assert invalid { apps.mail = app // { url = "file:///etc/passwd"; }; };
assert invalid { apps.mail = app // { url = "https://bad.example/\"quoted"; }; };
assert invalid { apps = { a = app // { id = "same"; }; b = app // { id = "same"; }; }; };
assert invalid { apps.mail = app // { extensions = [ { id = "firefox@example"; url = "https://example.invalid/addon"; } ]; }; };
pkgs.runCommand "nixpwamaker-gnosis-check" {
  nativeBuildInputs = [ pkgs.desktop-file-utils (pkgs.python3.withPackages (p: [p.pygobject3])) pkgs.glib ];
} ''
  desktop-file-validate ${desktop}
  grep -q '^X-Gnosis-Declarative=true$' ${desktop}
  export XDG_DATA_HOME="$TMPDIR/data"
  mkdir -p "$XDG_DATA_HOME/applications"
  ln -s ${desktop} "$XDG_DATA_HOME/applications/${desktopName}.desktop"
  export PWA_TEST_ARGS="$TMPDIR/gnosis-args"
  ${dispatcher}/bin/pwa-dispatcher 'https://mail.example/inbox?x=1&y=$hello'
  test "$(head -n1 "$PWA_TEST_ARGS")" = '--application-mode=${desktopName}.desktop'
  test "$(tail -n1 "$PWA_TEST_ARGS")" = 'https://mail.example/inbox?x=1&y=$hello'
  ${dispatcher}/bin/pwa-dispatcher 'https://unmatched.example/'
  test "$(cat "$PWA_TEST_ARGS")" = 'https://unmatched.example/'
  ${mixedDispatcher}/bin/pwa-dispatcher 'https://legacy.example/page?x=$value'
  test "$(sed -n '1p' "$PWA_TEST_ARGS")" = '--no-remote'
  test "$(sed -n '3p' "$PWA_TEST_ARGS")" = '/home/tester/.local/share/pwamaker-profiles/legacy'
  test "$(tail -n1 "$PWA_TEST_ARGS")" = 'https://legacy.example/page?x=$value'
  ${mixedDispatcher}/bin/pwa-dispatcher 'https://mail.example/mixed'
  test "$(head -n1 "$PWA_TEST_ARGS")" = '--application-mode=${desktopName}.desktop'
  rm "$PWA_TEST_ARGS"
  python3 - ${desktop} <<'PYTEST'
  import sys, time, os
  import gi
  gi.require_version("GioUnix", "2.0")
  from gi.repository import GioUnix
  info = GioUnix.DesktopAppInfo.new_from_filename(sys.argv[1])
  assert info is not None
  info.launch([], None)
  for _ in range(100):
      if os.path.exists(os.environ["PWA_TEST_ARGS"]):
          break
      time.sleep(0.01)
  with open(os.environ["PWA_TEST_ARGS"]) as stream:
      args = stream.read().splitlines()
  assert args == ["--application-mode=${desktopName}.desktop", ${builtins.toJSON app.url}], args
  PYTEST
  touch $out
''
