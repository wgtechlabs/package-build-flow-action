#!/usr/bin/env python3
"""Exercise real publish commands against local registries with fake tokens only."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
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

        class Handler(BaseHTTPRequestHandler):
            def do_PUT(self):
                self.rfile.read(int(self.headers.get("Content-Length", 0)))
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


if __name__ == "__main__":
    unittest.main()
