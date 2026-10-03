#!/usr/bin/env python3
"""Exercise real publish commands against local registries with fake tokens only."""

import base64
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tarfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ROOT = Path(__file__).resolve().parents[1]
NPM_TOKEN = "fake-npm-fixture-token"
GITHUB_TOKEN = "fake-github-fixture-token"


class RegistryAuthentication(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.requests = []
        self.tarballs = []
        self.urls = {}
        for registry, token in (("npm", NPM_TOKEN), ("github", GITHUB_TOKEN)):
            self.start_registry(registry, token)
        self.env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.root / "home"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "BUN_INSTALL_CACHE_DIR": str(self.root / "cache"),
            "CI": "true",
            "NPM_CONFIG_TOKEN": "wrong-inherited-token",
            "BUN_CONFIG_TOKEN": "wrong-inherited-bun-token",
            "NPM_TOKEN": NPM_TOKEN,
            "GITHUB_TOKEN": GITHUB_TOKEN,
            "NPM_REGISTRY_URL": self.urls["npm"],
            "GITHUB_REGISTRY_URL": self.urls["github"],
            "GITHUB_REPOSITORY_OWNER": "fixture",
            "REGISTRY": "both",
            "PACKAGE_VERSION": "0.1.0",
            "NPM_TAG": "latest",
            "PACKAGE_MANAGER": "bun",
            "BUILD_SCRIPT": "",
            "PUBLISH_ENABLED": "true",
            "PLANNED_PUBLISH": "true",
            "DRY_RUN": "false",
            "ACCESS": "public",
            "GITHUB_OUTPUT": str(self.root / "outputs"),
            "ACTION_PATH": str(ROOT),
            "npm_config_audit": "false",
            "npm_config_fund": "false",
        }
        Path(self.env["HOME"]).mkdir()
        Path(self.env["XDG_CONFIG_HOME"]).mkdir()
        Path(self.env["GITHUB_OUTPUT"]).touch()

    def start_registry(self, registry, token):
        requests = self.requests
        tarballs = self.tarballs

        class Handler(BaseHTTPRequestHandler):
            def do_PUT(self):
                payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                for attachment in payload.get('_attachments', {}).values():
                    if attachment.get('content_type') == 'application/octet-stream':
                        tarballs.append(base64.b64decode(attachment['data']))
                correct_token = self.headers.get("Authorization") == "Bearer " + token
                requests.append((registry, self.path, correct_token))
                self.send_response(201 if correct_token else 401)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"ok":true}' if correct_token else b'{"error":"unauthorized"}')

            def do_GET(self):
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b'{"error":"not_found"}')

            def log_message(self, *_args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.urls[registry] = f"http://127.0.0.1:{server.server_port}"

    def package(self, name="a"):
        directory = self.root / "packages" / name
        directory.mkdir(parents=True)
        path = directory / "package.json"
        path.write_text(json.dumps({"name": f"@fixture/{name}", "version": "0.1.0", "files": ["index.js"]}))
        (directory / "index.js").write_text("export const fixture = true;\n")
        self.env["PACKAGE_PATH"] = str(path)
        return path

    def run_script(self, script, expected_exit=0):
        result = subprocess.run(
            ["bash", str(ROOT / "scripts" / script)],
            cwd=self.root, env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, expected_exit, result.stdout + result.stderr)
        if script == 'configure-registries.sh':
            state = self.outputs().get('registry-backup-dir')
            if state:
                self.addCleanup(subprocess.run, ['bash', str(ROOT / 'scripts/registry-config-backup.sh'), 'restore', state],
                                cwd=self.root, env=self.env.copy(), capture_output=True, check=True)
        # The action must not print either configured token.
        for token in (NPM_TOKEN, GITHUB_TOKEN):
            self.assertNotIn(token, result.stdout + result.stderr)
        return result

    def outputs(self):
        return dict(line.split("=", 1) for line in Path(self.env["GITHUB_OUTPUT"]).read_text().splitlines() if "=" in line)

    def assert_published(self, registries):
        self.assertCountEqual([registry for registry, _, _ in self.requests], registries)
        self.assertTrue(all(correct for _, _, correct in self.requests), self.requests)

    def test_single_package_uses_each_registrys_token(self):
        self.package()
        self.run_script("configure-registries.sh")
        self.run_script("build-and-publish.sh")
        self.assert_published(["npm", "github"])
        self.assertEqual(self.outputs()["npm-published"], "true")
        self.assertEqual(self.outputs()["github-published"], "true")

    def test_selected_registry_only(self):
        self.package()
        for registry in ("npm", "github"):
            with self.subTest(registry=registry):
                self.requests.clear()
                self.env["REGISTRY"] = registry
                self.run_script("configure-registries.sh")
                self.run_script("build-and-publish.sh")
                self.assert_published([registry])

    def test_missing_selected_token_does_not_fall_back(self):
        self.package()
        self.run_script("configure-registries.sh")
        for registry, token_name in (("npm", "NPM_TOKEN"), ("github", "GITHUB_TOKEN")):
            with self.subTest(registry=registry):
                self.env["REGISTRY"] = registry
                original = self.env.pop(token_name)
                result = self.run_script("build-and-publish.sh", expected_exit=1)
                self.assertIn("A registry token is required for Bun publishing", result.stdout)
                self.assertEqual(self.requests, [])
                self.assertEqual(self.outputs()["artifact-published"], "false")
                self.env[token_name] = original

    def test_dry_run_makes_no_requests(self):
        self.package()
        self.env["DRY_RUN"] = "true"
        self.run_script("build-and-publish.sh")
        self.assertEqual(self.requests, [])
        self.assertEqual(self.outputs()["artifact-published"], "false")

    def test_monorepo_inherits_both_tokens(self):
        paths = [self.package(name) for name in ("a", "b")]
        self.env.update({
            "PACKAGE_PATHS": ",".join(str(path) for path in paths),
            "WORKSPACE_DETECTION": "false",
            "CHANGED_ONLY": "false",
            "DEPENDENCY_ORDER": "false",
            "AUDIT_ENABLED": "false",
            "MAIN_BRANCH": "main",
            "DEV_BRANCH": "dev",
            "GITHUB_CONTEXT": json.dumps({"event_name": "release", "sha": "0123456789abcdef", "event": {"release": {"tag_name": "v0.1.0", "prerelease": False}}}),
        })
        self.run_script("monorepo-orchestrator.sh")
        self.assert_published(["npm", "github", "npm", "github"])
        results = json.loads(self.outputs()["build-results"])
        self.assertEqual(len(results), 2)
        self.assertTrue(all(result["npm-published"] == result["github-published"] == "true" for result in results))

    def test_npm_publishing_keeps_npmrc_authentication(self):
        self.package()
        self.env["PACKAGE_MANAGER"] = "npm"
        self.run_script("configure-registries.sh")
        self.run_script("build-and-publish.sh")
        self.assert_published(["npm", "github"])

    def test_action_passes_tokens_to_both_publish_paths(self):
        action = (ROOT / "action.yml").read_text()
        for step_id in ("publish", "monorepo-orchestrator"):
            block = action.split(f"      id: {step_id}\n", 1)[1].split("    - name:", 1)[0]
            self.assertIn("NPM_TOKEN: ${{ inputs.npm-token }}", block)
            self.assertIn("GITHUB_TOKEN: ${{ inputs.github-token }}", block)

    def restore_registry_config(self):
        state = self.outputs()['registry-backup-dir']
        subprocess.run(['bash', str(ROOT / 'scripts/registry-config-backup.sh'), 'restore', state],
                       cwd=self.root, env=self.env, capture_output=True, check=True)
        self.assertFalse(Path(state).exists())

    def assert_tarballs_exclude_credentials(self):
        self.assertTrue(self.tarballs)
        for data in self.tarballs:
            with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                for member in archive.getmembers():
                    self.assertFalse(member.name.endswith('.npmrc.backup'), member.name)
                    if member.isfile():
                        contents = archive.extractfile(member).read()
                        for token in ('fake-existing-config-secret', NPM_TOKEN, GITHUB_TOKEN):
                            self.assertNotIn(token.encode(), contents, member.name)

    def test_root_packages_do_not_pack_credentials_and_restore_original_config(self):
        workspace = self.root
        original = '//registry.npmjs.org/:_authToken=fake-existing-config-secret\n'
        for manager in ('npm', 'bun'):
            with self.subTest(manager=manager):
                self.root = workspace / manager
                self.root.mkdir()
                package = self.root / 'package.json'
                package.write_text(json.dumps({'name': '@fixture/root', 'version': '0.1.0'}))
                (self.root / 'index.js').write_text('export const fixture = true;\n')
                config = self.root / '.npmrc'
                config.write_text(original)
                config.chmod(0o600)
                self.env.update({'PACKAGE_PATH': str(package), 'PACKAGE_MANAGER': manager})
                self.tarballs.clear()
                self.run_script('configure-registries.sh')
                self.assertEqual(config.stat().st_mode & 0o777, 0o600)
                state = Path(self.outputs()['registry-backup-dir'])
                self.assertNotIn(self.root, state.parents)
                self.assertEqual(state.stat().st_mode & 0o777, 0o700)
                self.run_script('build-and-publish.sh')
                self.restore_registry_config()
                self.assert_tarballs_exclude_credentials()
                self.assertEqual(config.read_text(), original)
                self.assertEqual(config.stat().st_mode & 0o777, 0o600)
                self.assertFalse((self.root / '.npmrc.backup').exists())

    def test_monorepo_restores_root_and_package_configs_without_packing_credentials(self):
        workspace = self.root
        original = '//registry.npmjs.org/:_authToken=fake-existing-config-secret\n'
        for manager in ('npm', 'bun'):
            with self.subTest(manager=manager):
                self.root = workspace / manager
                self.root.mkdir()
                paths = [self.package(name) for name in ('a', 'b')]
                for package in paths:
                    manifest = json.loads(package.read_text())
                    manifest.pop('files')
                    package.write_text(json.dumps(manifest))
                configs = [self.root / '.npmrc', *(package.parent / '.npmrc' for package in paths)]
                for config in configs:
                    config.write_text(original)
                self.env.update({
                    'PACKAGE_PATHS': ','.join(str(package) for package in paths), 'PACKAGE_MANAGER': manager,
                    'WORKSPACE_DETECTION': 'false', 'CHANGED_ONLY': 'false', 'DEPENDENCY_ORDER': 'false',
                    'AUDIT_ENABLED': 'false', 'MAIN_BRANCH': 'main', 'DEV_BRANCH': 'dev',
                    'GITHUB_CONTEXT': json.dumps({'event_name': 'release', 'sha': '0123456789abcdef', 'event': {'release': {'tag_name': 'v0.1.0', 'prerelease': False}}}),
                })
                self.tarballs.clear()
                self.run_script('monorepo-orchestrator.sh')
                self.assert_tarballs_exclude_credentials()
                for config in configs:
                    self.assertEqual(config.read_text(), original)
                self.assertFalse(list(self.root.rglob('.npmrc.backup')))
                state = self.outputs()['registry-backup-dir']
                self.assertFalse(Path(state).exists())

    def test_configuration_failure_restores_existing_configs(self):
        package = self.package()
        original = 'save-exactly=true\n'
        configs = [self.root / '.npmrc', package.parent / '.npmrc']
        for config in configs:
            config.write_text(original)
        self.env['NPM_TOKEN'] = ''
        self.run_script('configure-registries.sh', expected_exit=1)
        for config in configs:
            self.assertEqual(config.read_text(), original)
        self.assertFalse(Path(self.outputs()['registry-backup-dir']).exists())

    def test_nested_config_links_are_replaced_without_overwriting_packaged_files(self):
        for manager in ('npm', 'bun'):
            for link_type in ('symlink', 'hardlink'):
                with self.subTest(manager=manager, link_type=link_type):
                    package = self.package(manager + '-' + link_type)
                    manifest = json.loads(package.read_text())
                    manifest.pop('files')
                    package.write_text(json.dumps(manifest))
                    marker = package.parent / 'public-marker.txt'
                    original = b'strict-ssl=true\n'
                    marker.write_bytes(original)
                    config = package.parent / '.npmrc'
                    if link_type == 'symlink':
                        config.symlink_to(marker)
                    else:
                        os.link(marker, config)
                    self.env['PACKAGE_MANAGER'] = manager
                    self.tarballs.clear()
                    self.run_script('configure-registries.sh')
                    self.run_script('build-and-publish.sh')
                    self.assertFalse(config.is_symlink())
                    self.assertNotEqual(config.stat().st_ino, marker.stat().st_ino)
                    self.assertEqual(config.stat().st_mode & 0o777, 0o600)
                    self.assertEqual(marker.read_bytes(), original)
                    self.assert_tarballs_exclude_credentials()
                    for data in self.tarballs:
                        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                            self.assertEqual(archive.extractfile('package/public-marker.txt').read(), original)
                    self.restore_registry_config()
                    self.assertEqual(config.read_bytes(), original)
                    self.assertEqual(marker.read_bytes(), original)
                    self.assertEqual(config.is_symlink(), link_type == 'symlink')

    def test_oidc_captures_original_workspace_ignore_scripts_with_env_precedence(self):
        package = self.package()
        (self.root / 'package.json').write_text(json.dumps({'private': True, 'workspaces': ['packages/*']}))
        (self.root / '.npmrc').write_text('ignore-scripts=true\n')
        self.env.update({'NPM_AUTH_METHOD': 'oidc', 'REGISTRY': 'npm'})
        self.run_script('configure-registries.sh')
        self.assertEqual(self.outputs()['npm-ignore-scripts'], 'true')
        self.restore_registry_config()
        self.env['npm_config_ignore_scripts'] = 'false'
        self.run_script('configure-registries.sh')
        self.assertEqual(self.outputs()['npm-ignore-scripts'], 'false')
        self.restore_registry_config()
        self.assertEqual((self.root / '.npmrc').read_text(), 'ignore-scripts=true\n')

    def test_monorepo_validation_keeps_existing_package_config_symlink(self):
        package = self.package()
        manifest = json.loads(package.read_text())
        manifest['scripts'] = {'build': 'test -L .npmrc'}
        package.write_text(json.dumps(manifest))
        original = self.root / 'original-config'
        original.write_text('strict-ssl=true\n')
        config = package.parent / '.npmrc'
        config.symlink_to(original)
        self.env.update({
            'PACKAGE_PATHS': str(package), 'PACKAGE_MANAGER': 'npm', 'BUILD_SCRIPT': 'build',
            'NPM_TOKEN': '', 'GITHUB_TOKEN': '', 'PUBLISH_ENABLED': 'false',
            'WORKSPACE_DETECTION': 'false', 'CHANGED_ONLY': 'false', 'DEPENDENCY_ORDER': 'false',
            'AUDIT_ENABLED': 'false', 'MAIN_BRANCH': 'main', 'DEV_BRANCH': 'dev',
            'GITHUB_CONTEXT': json.dumps({'event_name': 'release', 'sha': '0123456789abcdef', 'event': {'release': {'tag_name': 'v0.1.0', 'prerelease': False}}}),
        })
        self.run_script('monorepo-orchestrator.sh')
        self.assertTrue(config.is_symlink())
        self.assertEqual(config.read_text(), 'strict-ssl=true\n')
        self.assertFalse((self.root / '.npmrc').exists())

    def test_build_failure_cleanup_removes_created_config(self):
        package = self.package()
        manifest = json.loads(package.read_text())
        manifest['scripts'] = {'build': 'exit 1'}
        package.write_text(json.dumps(manifest))
        self.env['BUILD_SCRIPT'] = 'build'
        self.run_script('configure-registries.sh')
        self.run_script('build-and-publish.sh', expected_exit=1)
        self.restore_registry_config()
        self.assertFalse((self.root / '.npmrc').exists())
        self.assertFalse((package.parent / '.npmrc').exists())
        action = (ROOT / 'action.yml').read_text()
        cleanup = action.split('    - name: Restore Registry Configuration\n', 1)[1]
        self.assertIn('if: always()', cleanup)


if __name__ == "__main__":
    unittest.main()
