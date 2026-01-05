"""
Firefox PWA Sync Engine (NixOS/Home Manager)
Refined: Support for Gnome Headerbar (TabsToolbar) layout injection.
Linter Fix: Removed unused imports, fixed trailing whitespace and bare excepts.
"""

import argparse
import json
import os
import shutil
import random
import re
import urllib.request
from urllib.parse import urlparse
from pathlib import Path
from typing import List, Dict, Optional


# --- UTILS ---


def log(tag: str, msg: str, color: str = "37"):
    """Simple colored logging."""
    colors = {"green": "32", "yellow": "33", "red": "31", "blue": "34"}
    c = colors.get(color, "37")
    print(f"\033[{c}m[{tag}] {msg}\033[0m")


def generate_ulid() -> str:
    """Generates a Firefox-compatible ULID."""
    base32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    first = random.choice("01234567")
    rest = "".join(random.choices(base32, k=25))
    return (first + rest).upper()


# --- CONTEXT ---


class SystemContext:
    def __init__(self):
        # Resolve XDG paths
        home = Path.home()
        self.xdg_data = Path(os.environ.get("XDG_DATA_HOME", home / ".local" / "share"))
        self.fpwa_root = self.xdg_data / "firefoxpwa"
        self.sites_dir = self.fpwa_root / "sites"
        self.profiles_dir = self.fpwa_root / "profiles"
        self.global_config = self.fpwa_root / "config.json"
        self.desktop_dir = self.xdg_data / "applications"


# --- CORE LOGIC ---


class PWAProfileFactory:
    """Handles the dirty work of filesystem copying and cleaning."""

    def __init__(self, ctx: SystemContext):
        self.ctx = ctx

    def create_from_template(self, profile_id: str, template_path: str) -> bool:
        """Clones a template into a new profile ID."""
        source = Path(template_path)
        dest = self.ctx.profiles_dir / profile_id

        if not source.exists():
            log("!", f"Template not found: {source}", "red")
            return False

        if dest.exists():
            shutil.rmtree(dest)

        # Copy Template
        shutil.copytree(
            source, dest,
            ignore=shutil.ignore_patterns('lock', '.parentlock'),
            dirs_exist_ok=True
        )

        # Fix Nix Store Permissions (chmod +w)
        os.chmod(dest, 0o755)
        for root, dirs, files in os.walk(dest):
            for d in dirs:
                os.chmod(os.path.join(root, d), 0o755)
            for f in files:
                os.chmod(os.path.join(root, f), 0o644)

        self._sanitize(dest)
        return True

    def _sanitize(self, profile_path: Path):
        """Removes stateful garbage that shouldn't be inherited."""
        garbage = [
            "compatibility.ini", "search.json.mozlz4", "startupCache",
            "extensions.json", "extensions", "addonStartup.json.lz4",
            "extension-preferences.json", "extension-settings.json",
            "addons.json"
        ]
        for item in garbage:
            p = profile_path / item
            if p.exists():
                if p.is_dir():
                    shutil.rmtree(p)
                else:
                    p.unlink()

    def inject_policies(self, profile_path: Path, addons: List[str], extra_policies: Dict):
        """Creates distribution/policies.json."""
        dist_dir = profile_path / "distribution"
        dist_dir.mkdir(parents=True, exist_ok=True)

        policy_data = {
            "policies": {
                "ExtensionSettings": {"*": {"installation_mode": "blocked"}},
                **extra_policies
            }
        }

        for addon in addons:
            if ":" not in addon:
                continue
            aid, url = addon.split(":", 1)
            policy_data["policies"]["ExtensionSettings"][aid] = {
                "install_url": url,
                "installation_mode": "force_installed",
                "default_area": "menupanel"
            }

        policy_dest = dist_dir / "policies.json"
        with open(policy_dest, "w") as f:
            json.dump(policy_data, f, indent=2)

    def inject_prefs(self, profile_path: Path, layout: str):
        """Writes/Overwrites user.js."""
        user_js = profile_path / "user.js"
        ua = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"

        lines = [
            f'user_pref("general.useragent.override", "{ua}");',
            'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);',
            'user_pref("extensions.autoDisableScopes", 0);',
        ]

        if layout:
            layout_json = self._build_layout_json(layout)
            lines.append(f'user_pref("browser.uiCustomization.state", "{layout_json}");')

        # [!] OVERWRITE mode "w" instead of "a" to prevent duplicate layout lines
        with open(user_js, "w") as f:
            f.write("\n" + "\n".join(lines) + "\n")

    def _build_layout_json(self, layout_str: str) -> str:
        """Splits layout at 'spring' for Gnome Headerbar compatibility."""
        mapping = {
            "back": ["back-button"],
            "forward": ["forward-button"],
            "arrows": ["back-button", "forward-button"],
            "refresh": ["stop-reload-button"],
            "home": ["home-button"],
            "extensions": ["unified-extensions-button"],
            "spacer": ["spacer"],
            "spring": ["spring"]
        }

        items = layout_str.split(",")
        left_items, right_items = [], []
        target = left_items

        for item in items:
            key = item.strip().lower()
            if key == "spring":
                target = right_items
                continue
            val = mapping.get(key)
            if val:
                target.extend(val)

        # TabsToolbar items surround the actual tabs
        tabs_toolbar = (
            ["site-info"] + left_items + ["tabbrowser-tabs", "new-tab-button", "alltabs-button"] + right_items
        )

        data = {
            "placements": {
                "nav-bar": ["sidebar-button", "close-page-button", "urlbar-container", "vertical-spacer"],
                "toolbar-menubar": ["menubar-items"],
                "TabsToolbar": tabs_toolbar,
                "PersonalToolbar": ["personal-bookmarks"],
                "unified-extensions-area": [],
                "vertical-tabs": []
            },
            "seen": ["unified-extensions-button", "stop-reload-button", "home-button"],
            "dirtyAreaCache": [],  # Forces Firefox to reset its toolbar state
            "currentVersion": 23,   # Matched to your prefs.js version
            "newElementCount": 0
        }
        # Use compact separators and escape quotes for user.js
        return json.dumps(data, separators=(',', ':')).replace('"', '\\"')


# --- STATE MANAGER ---


class StateManager:
    """Handles the FirefoxPWA Registry (config.json) and Desktop Files."""

    def __init__(self, ctx: SystemContext):
        self.ctx = ctx

    def get_registry(self) -> Dict:
        if self.ctx.global_config.exists():
            try:
                with open(self.ctx.global_config) as f:
                    return json.load(f)
            except Exception:
                pass
        return {"profiles": {}, "sites": {}}

    def save_registry(self, data: Dict):
        self.ctx.fpwa_root.mkdir(parents=True, exist_ok=True)
        with open(self.ctx.global_config, "w") as f:
            json.dump(data, f, separators=(',', ':'))

    def scan_desktop_files(self) -> Dict[str, dict]:
        """Returns map of {App Name: {path, site_id}}."""
        found = {}
        if not self.ctx.desktop_dir.exists():
            return found

        rx_name = re.compile(r"^Name=(.+)$", re.MULTILINE)
        rx_site = re.compile(r"^X-FirefoxPWA-Site=(.+)$", re.MULTILINE)

        for entry in self.ctx.desktop_dir.glob("*-fpwa.desktop"):
            try:
                txt = entry.read_text()
                name_m = rx_name.search(txt)
                site_m = rx_site.search(txt)
                if name_m and site_m:
                    found[name_m.group(1)] = {
                        "path": entry,
                        "site_id": site_m.group(1)
                    }
            except Exception:
                continue
        return found

    def nuke(self, name: str, meta: dict):
        """Deletes a PWA from filesystem and registry."""
        log("-", f"Pruning orphaned PWA: {name}", "yellow")
        if meta['path'].exists():
            meta['path'].unlink()

        reg = self.get_registry()
        site_id = meta['site_id']
        profile_id = reg.get("sites", {}).get(site_id, {}).get("profile")

        if site_id in reg.get("sites", {}):
            del reg["sites"][site_id]
        if profile_id and profile_id in reg.get("profiles", {}):
            del reg["profiles"][profile_id]
        self.save_registry(reg)

        if site_id:
            shutil.rmtree(self.ctx.sites_dir / site_id, ignore_errors=True)
        if profile_id:
            shutil.rmtree(self.ctx.profiles_dir / profile_id, ignore_errors=True)


# --- ORCHESTRATOR ---


class PWAOrchestrator:
    def __init__(self, ctx: SystemContext):
        self.ctx = ctx
        self.factory = PWAProfileFactory(ctx)
        self.state = StateManager(ctx)

    def sync(self, manifest: Dict):
        existing_apps = self.state.scan_desktop_files()
        desired_names = set(manifest.keys())

        # 1. Prune
        for name, meta in existing_apps.items():
            if name not in desired_names:
                self.state.nuke(name, meta)

        # 2. Deploy/Update
        for name, config in manifest.items():
            self.deploy(name, config, existing_apps.get(name))

    def resolve_url(self, url: str) -> str:
        try:
            req = urllib.request.Request(url, method="HEAD")
            req.add_header("User-Agent", "Mozilla/5.0 (Linux; Android 10)")
            with urllib.request.urlopen(req, timeout=3) as r:
                return r.geturl()
        except Exception:
            return url

    def deploy(self, name: str, config: Dict, existing_meta: Optional[Dict]):
        log("*" if existing_meta else "+", f"{'Updating' if existing_meta else 'Creating'}: {name}", "blue")

        url = self.resolve_url(config['url'])
        icon = config.get('icon')
        template = config.get('templateProfile')

        reg = self.state.get_registry()

        if existing_meta:
            site_id = existing_meta['site_id']
            profile_id = reg.get("sites", {}).get(site_id, {}).get("profile")
            if not profile_id:
                profile_id = generate_ulid()
        else:
            site_id = generate_ulid()
            profile_id = generate_ulid()

        site_path = self.ctx.sites_dir / site_id
        site_path.mkdir(parents=True, exist_ok=True)

        web_manifest = {
            "name": name, "short_name": name, "start_url": url,
            "scope": f"{urlparse(url).scheme}://{urlparse(url).netloc}/",
            "display": "standalone", "background_color": "#000000", "theme_color": "#000000",
            "icons": [{"src": "icon.png", "sizes": "512x512", "type": "image/png", "purpose": "any"}]
        }
        with open(site_path / "manifest.json", "w") as f:
            json.dump(web_manifest, f)

        if icon and os.path.exists(icon):
            shutil.copy(icon, site_path / "icon.png")

        profile_path = self.ctx.profiles_dir / profile_id
        if not profile_path.exists():
            if template:
                self.factory.create_from_template(profile_id, template)
            else:
                log("!", f"No template for {name}", "red")

        if profile_path.exists():
            # Injecting per-app layout and specific extensions
            self.factory.inject_prefs(profile_path, config.get('layout', ''))
            self.factory.inject_policies(profile_path, config.get('extensions', []), config.get('extraPolicies', {}))

        reg["profiles"][profile_id] = {"ulid": profile_id, "name": name, "sites": [site_id]}
        reg["sites"][site_id] = {
            "ulid": site_id, "profile": profile_id,
            "config": {"document_url": url, "manifest_url": url}, "manifest": web_manifest
        }
        self.state.save_registry(reg)

        self._write_desktop_entry(name, site_id, site_path, icon, config)

    def _write_desktop_entry(self, name, site_id, site_path, icon_source, config):
        safe_slug = "".join(c for c in name if c.isalnum()).lower()
        icon_str = f"{site_path}/icon.png" if icon_source and os.path.exists(icon_source) else (icon_source or f"{site_path}/icon.png")
        mime_types = config.get('mimeTypes', [])
        mime_line = f"MimeType={';'.join(mime_types)};\n" if mime_types else ""
        categories = config.get('categories', [])
        cat_str = ";".join(categories) + (";" if categories and not categories[-1].endswith(";") else "")
        cat_line = f"Categories={cat_str}\n" if cat_str else "Categories=Network;WebBrowser;\n"
        keywords = config.get('keywords', [])
        key_str = ";".join(keywords) + (";" if keywords and not keywords[-1].endswith(";") else "")
        key_line = f"Keywords={key_str}\n" if key_str else ""

        content = (
            "[Desktop Entry]\n"
            f"Name={name}\n"
            f"Exec=firefoxpwa site launch {site_id}\n"
            "Type=Application\n"
            "Terminal=false\n"
            f"Icon={icon_str}\n"
            f"StartupWMClass=FFPWA-{site_id}\n"
            f"{mime_line}{cat_line}{key_line}"
            f"X-FirefoxPWA-Site={site_id}\n"
        )
        dest = self.ctx.desktop_dir / f"{safe_slug}-fpwa.desktop"
        self.ctx.desktop_dir.mkdir(parents=True, exist_ok=True)
        with open(dest, "w") as f:
            f.write(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    with open(args.manifest, "r") as f:
        data = json.load(f)
    PWAOrchestrator(SystemContext()).sync(data)
