#!/usr/bin/env python3
"""Use real npm OIDC exchange against local fake issuer/registries only."""
import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import threading
import tarfile
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

spec = importlib.util.spec_from_file_location('token_auth', Path(__file__).with_name('bun-registry-auth.py'))
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)
ROOT = auth.ROOT
EPHEMERAL_TOKEN = 'fake-ephemeral-npm-token'
REQUEST_TOKEN = 'fake-github-oidc-request-token'
JWT = 'eyJhbGciOiJub25lIn0.' + base64.urlsafe_b64encode(b'{"repository_visibility":"private"}').decode().rstrip('=') + '.fake'


class TrustedPublishing(unittest.TestCase):
    package = auth.RegistryAuthentication.package
    run_script = auth.RegistryAuthentication.run_script
    outputs = auth.RegistryAuthentication.outputs
    assert_published = auth.RegistryAuthentication.assert_published

    def setUp(self):
        self.exchange_fails = False
        self.oidc_requests = []
        self.published_documents = []
        self.publish_receipt = None
        auth.RegistryAuthentication.setUp(self)
        self.env.update({
            'NPM_AUTH_METHOD': 'oidc',
            'GITHUB_ACTIONS': 'true',
            'RUNNER_ENVIRONMENT': 'github-hosted',
            'ACTIONS_ID_TOKEN_REQUEST_URL': self.urls['npm'] + '/id-token',
            'ACTIONS_ID_TOKEN_REQUEST_TOKEN': REQUEST_TOKEN,
            'NODE_AUTH_TOKEN': 'wrong-legacy-node-token',
            'npm_config__authToken': 'wrong-global-npm-token',
            'NPM_ID_TOKEN': 'wrong-preexisting-id-token',
        })
        self.env.pop('NPM_TOKEN')
        self.env['NPM_CONFIG_USERCONFIG'] = str(self.root / 'legacy.npmrc')
        Path(self.env['NPM_CONFIG_USERCONFIG']).write_text(f"//127.0.0.1:{self.urls['npm'].rsplit(':', 1)[1]}/:_authToken=wrong-userconfig-token\n")

    def start_registry(self, registry, token):
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def respond(self, code, value):
                self.send_response(code)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(value).encode())

            def do_GET(self):
                if self.path.startswith('/id-token'):
                    owner.oidc_requests.append(('identity', self.headers.get('Authorization') == 'Bearer ' + REQUEST_TOKEN))
                    self.respond(200, {'value': JWT})
                else:
                    self.respond(404, {'error': 'not_found'})

            def do_POST(self):
                self.rfile.read(int(self.headers.get('Content-Length', 0)))
                valid = self.path.startswith('/-/npm/v1/oidc/token/exchange/package/') and self.headers.get('Authorization') == 'Bearer ' + JWT
                owner.oidc_requests.append(('exchange', valid))
                self.respond(403 if owner.exchange_fails else 200, {'error': 'denied'} if owner.exchange_fails else {'token': EPHEMERAL_TOKEN})

            def do_PUT(self):
                document = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
                owner.published_documents.append((registry, document))
                expected = EPHEMERAL_TOKEN if registry == 'npm' else token
                correct = self.headers.get('Authorization') == 'Bearer ' + expected
                owner.requests.append((registry, self.path, correct))
                if correct and registry == 'npm' and owner.publish_receipt is not None:
                    owner.publish_receipt.write_text('uploaded')
                self.respond(201 if correct else 401, {'ok': correct})

            def log_message(self, *_args):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.urls[registry] = f'http://127.0.0.1:{server.server_port}'

    def configure(self):
        self.run_script('configure-registries.sh')
        config = (self.root / '.npmrc').read_text()
        self.assertNotIn(auth.NPM_TOKEN, config)
        self.assertNotIn(self.urls['npm'].replace('http:', '') + '/:_authToken', config)

    def test_bun_oidc_and_github_use_separate_authentication(self):
        self.package()
        self.env['NPM_TOKEN'] = auth.NPM_TOKEN  # Explicitly ignored in OIDC mode.
        self.configure()
        result = self.run_script('build-and-publish.sh')
        self.assert_published(['npm', 'github'])
        self.assertEqual(self.oidc_requests, [('identity', True), ('exchange', True)])
        self.assertEqual(self.outputs()['npm-published'], 'true')
        for secret in (EPHEMERAL_TOKEN, REQUEST_TOKEN, JWT):
            self.assertNotIn(secret, result.stdout + result.stderr)

    def test_npm_project_uses_oidc(self):
        self.package()
        self.env.update({'PACKAGE_MANAGER': 'npm', 'REGISTRY': 'npm'})
        self.configure()
        self.run_script('build-and-publish.sh')
        self.assert_published(['npm'])
        self.assertEqual(self.oidc_requests, [('identity', True), ('exchange', True)])

    def test_rejecting_prepublish_only_blocks_oidc_and_upload_for_each_manager(self):
        for manager in ('npm', 'bun'):
            with self.subTest(manager=manager):
                package = self.package(manager)
                manifest = json.loads(package.read_text())
                manifest['scripts'] = {'prepublishOnly': 'echo release-check-blocked >&2; exit 19'}
                package.write_text(json.dumps(manifest))
                self.env.update({'PACKAGE_MANAGER': manager, 'REGISTRY': 'npm'})
                self.configure()
                result = self.run_script('build-and-publish.sh', expected_exit=1)
                self.assertIn('release-check-blocked', result.stdout + result.stderr)
                self.assertEqual(self.oidc_requests + self.requests, [])
                self.assertEqual(self.outputs()['npm-published'], 'false')
                self.assertEqual(self.outputs()['artifact-published'], 'false')

    def test_prepublish_only_build_output_is_in_uploaded_tarball_for_each_manager(self):
        for manager in ('npm', 'bun'):
            with self.subTest(manager=manager):
                self.requests.clear()
                self.oidc_requests.clear()
                self.published_documents.clear()
                package = self.package(manager)
                manifest = json.loads(package.read_text())
                manifest['scripts'] = {
                    'prepublishOnly': "printf 'built by prepublishOnly' > index.js; echo prepublishOnly > lifecycle.log",
                    'prepublish': 'echo prepublish >> lifecycle.log',
                    'prepack': 'echo prepack >> lifecycle.log',
                    'prepare': 'echo prepare >> lifecycle.log',
                    'postpack': 'echo postpack >> lifecycle.log',
                    'publish': 'test -f upload-receipt && echo publish >> lifecycle.log',
                    'postpublish': 'test -f upload-receipt && echo postpublish >> lifecycle.log',
                }
                self.publish_receipt = package.parent / 'upload-receipt'
                package.write_text(json.dumps(manifest))
                (package.parent / 'index.js').unlink()
                self.env.update({'PACKAGE_MANAGER': manager, 'REGISTRY': 'npm'})
                self.configure()
                self.run_script('build-and-publish.sh')
                self.assert_published(['npm'])
                self.assertEqual(self.oidc_requests, [('identity', True), ('exchange', True)])
                registry, document = self.published_documents[0]
                self.assertEqual(registry, 'npm')
                attachment = next(iter(document['_attachments'].values()))
                with tarfile.open(fileobj=io.BytesIO(base64.b64decode(attachment['data'])), mode='r:gz') as packed:
                    self.assertEqual(packed.extractfile('package/index.js').read(), b'built by prepublishOnly')
                self.assertEqual(self.outputs()['npm-published'], 'true')
                self.assertEqual((package.parent / 'lifecycle.log').read_text().splitlines(),
                                 ['prepublishOnly', 'prepack', 'prepare', 'postpack', 'publish', 'postpublish'])

    def test_failed_upload_never_runs_publish_or_postpublish_hooks(self):
        self.exchange_fails = True
        for manager in ('npm', 'bun'):
            with self.subTest(manager=manager):
                package = self.package(manager)
                manifest = json.loads(package.read_text())
                manifest['scripts'] = {'publish': 'echo publish >> after-upload',
                                       'postpublish': 'echo postpublish >> after-upload'}
                package.write_text(json.dumps(manifest))
                self.env.update({'PACKAGE_MANAGER': manager, 'REGISTRY': 'npm'})
                self.configure()
                self.run_script('build-and-publish.sh', expected_exit=1)
                self.assertFalse((package.parent / 'after-upload').exists())
                self.assertEqual(self.requests, [])

    def test_publish_hook_failure_reports_failure_after_upload(self):
        for manager in ('npm', 'bun'):
            with self.subTest(manager=manager):
                self.requests.clear()
                package = self.package(manager)
                manifest = json.loads(package.read_text())
                manifest['scripts'] = {'publish': 'echo post-upload-failed >&2; exit 19',
                                       'postpublish': 'echo should-not-run > postpublish-ran'}
                package.write_text(json.dumps(manifest))
                self.env.update({'PACKAGE_MANAGER': manager, 'REGISTRY': 'npm'})
                self.configure()
                result = self.run_script('build-and-publish.sh', expected_exit=1)
                self.assertIn('post-upload-failed', result.stdout + result.stderr)
                self.assert_published(['npm'])  # Publication happened before the failing hook.
                self.assertFalse((package.parent / 'postpublish-ran').exists())
                self.assertEqual(self.outputs()['npm-published'], 'false')

    def test_npm_ignore_scripts_controls_explicit_publish_hooks_for_each_manager(self):
        for manager in ('npm', 'bun'):
            with self.subTest(manager=manager):
                self.requests.clear()
                package = self.package(manager)
                manifest = json.loads(package.read_text())
                manifest['scripts'] = {event: 'echo hook-must-not-run >&2; exit 19'
                                       for event in ('prepublishOnly', 'publish', 'postpublish')}
                manifest['scripts'].update({event: f'echo {event} >> pack-hooks'
                                            for event in ('prepack', 'prepare', 'postpack')})
                package.write_text(json.dumps(manifest))
                self.env.update({'PACKAGE_MANAGER': manager, 'REGISTRY': 'npm', 'npm_config_ignore_scripts': 'true'})
                self.configure()
                result = self.run_script('build-and-publish.sh')
                self.assertNotIn('hook-must-not-run', result.stdout + result.stderr)
                self.assert_published(['npm'])
                pack_hooks = package.parent / 'pack-hooks'
                if manager == 'bun':
                    # Bun's install/pack lifecycle still follows Bun's own configuration.
                    self.assertIn('prepack', pack_hooks.read_text().splitlines())
                    self.assertIn('postpack', pack_hooks.read_text().splitlines())
                else:
                    self.assertFalse(pack_hooks.exists())

    def test_monorepo_inherits_oidc_without_npm_token(self):
        paths = [self.package(name) for name in ('a', 'b')]
        self.env.update({
            'PACKAGE_PATHS': ','.join(str(path) for path in paths),
            'WORKSPACE_DETECTION': 'false',
            'CHANGED_ONLY': 'false',
            'DEPENDENCY_ORDER': 'false',
            'AUDIT_ENABLED': 'false',
            'MAIN_BRANCH': 'main',
            'DEV_BRANCH': 'dev',
            'GITHUB_CONTEXT': json.dumps({'event_name': 'release', 'sha': '0123456789abcdef', 'event': {'release': {'tag_name': 'v0.1.0', 'prerelease': False}}}),
        })
        self.run_script('monorepo-orchestrator.sh')
        self.assert_published(['npm', 'github', 'npm', 'github'])
        self.assertEqual(self.oidc_requests, [('identity', True), ('exchange', True)] * 2)
        results = json.loads(self.outputs()['build-results'])
        self.assertTrue(all(result['npm-published'] == result['github-published'] == 'true' for result in results))

    def test_failed_exchange_cannot_fall_back_to_any_long_lived_token(self):
        self.package()
        self.env['REGISTRY'] = 'npm'
        self.env['NPM_TOKEN'] = auth.NPM_TOKEN
        self.exchange_fails = True
        self.configure()
        # Also leave a credential in the project config to prove cwd isolation.
        with (self.root / '.npmrc').open('a') as config:
            config.write(self.urls['npm'].replace('http:', '') + '/:_authToken=wrong-project-token\n')
        self.run_script('build-and-publish.sh', expected_exit=1)
        self.assertEqual(self.oidc_requests, [('identity', True), ('exchange', True)])
        self.assertEqual(self.requests, [])
        self.assertEqual(self.outputs()['artifact-published'], 'false')

    def test_missing_oidc_permission_fails_before_registry_requests(self):
        self.package()
        self.env['REGISTRY'] = 'npm'
        self.env.pop('ACTIONS_ID_TOKEN_REQUEST_TOKEN')
        self.configure()
        result = self.run_script('build-and-publish.sh', expected_exit=1)
        self.assertIn('id-token: write', result.stderr)
        self.assertEqual(self.oidc_requests + self.requests, [])

    def test_non_loopback_http_registry_is_rejected_before_packing(self):
        package = self.package()
        manifest = json.loads(package.read_text())
        manifest['scripts'] = {'prepack': 'echo packed > pack-ran'}
        package.write_text(json.dumps(manifest))
        self.env['REGISTRY'] = 'npm'
        for host in ('registry.example.test', 'localhost.example.test', '127.0.0.1.example.test', '[::2]'):
            with self.subTest(host=host):
                self.env['NPM_REGISTRY_URL'] = 'http://' + host
                self.configure()
                result = self.run_script('build-and-publish.sh', expected_exit=1)
                self.assertIn('requires HTTPS except for loopback registries', result.stderr)
                self.assertFalse((package.parent / 'pack-ran').exists())
                self.assertEqual(self.oidc_requests + self.requests, [])

    def test_validation_modes_never_request_oidc(self):
        self.package()
        self.env['REGISTRY'] = 'npm'
        self.env.pop('ACTIONS_ID_TOKEN_REQUEST_TOKEN')
        self.configure()
        for setting in ('DRY_RUN', 'BOT_DRY_RUN', 'PUBLISH_ENABLED'):
            with self.subTest(setting=setting):
                self.env[setting] = 'false' if setting == 'PUBLISH_ENABLED' else 'true'
                self.run_script('build-and-publish.sh')
                self.env[setting] = 'true' if setting == 'PUBLISH_ENABLED' else 'false'
                self.assertEqual(self.oidc_requests + self.requests, [])
                self.assertEqual(self.outputs()['artifact-published'], 'false')

    def test_unknown_auth_method_is_rejected(self):
        self.package()
        self.env['NPM_AUTH_METHOD'] = 'typo'
        self.run_script('configure-registries.sh', expected_exit=1)
        self.run_script('build-and-publish.sh', expected_exit=1)
        self.assertEqual(self.oidc_requests + self.requests, [])

    def test_publish_config_cannot_supply_fallback_credentials(self):
        package = self.package()
        manifest = json.loads(package.read_text())
        manifest['publishConfig'] = {'_authToken': 'wrong-manifest-token'}
        package.write_text(json.dumps(manifest))
        self.env['REGISTRY'] = 'npm'
        self.configure()
        result = self.run_script('build-and-publish.sh', expected_exit=1)
        self.assertIn('publishConfig must not contain credentials', result.stderr)
        self.assertEqual(self.oidc_requests + self.requests, [])

    def test_old_npm_cli_is_rejected(self):
        self.package()
        self.env['REGISTRY'] = 'npm'
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        command = bin_dir / 'npm'
        command.write_text('#!/bin/sh\nif [ "$1" = "--version" ]; then echo 11.5.0; exit 0; fi\nexit 99\n')
        command.chmod(0o755)
        self.env['PATH'] = str(bin_dir) + os.pathsep + self.env['PATH']
        self.configure()
        result = self.run_script('build-and-publish.sh', expected_exit=1)
        self.assertIn('npm >=11.5.1', result.stderr)
        self.assertEqual(self.oidc_requests + self.requests, [])

    def test_action_wires_auth_method_to_all_paths(self):
        action = (ROOT / 'action.yml').read_text()
        for step_id in ('publish', 'configure-registries', 'monorepo-orchestrator'):
            block = action.split(f'      id: {step_id}\n', 1)[1].split('    - name:', 1)[0]
            self.assertIn('NPM_AUTH_METHOD: ${{ inputs.npm-auth-method }}', block)


if __name__ == '__main__':
    unittest.main()
