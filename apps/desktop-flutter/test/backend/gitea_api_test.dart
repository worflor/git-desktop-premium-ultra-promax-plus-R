// Gitea/Forgejo REST integration — exercised end to end against a local
// dart:io fake server. Real HTTP flows through the production client code
// (giteaGet/_post/_patch/_delete, the 429 retry, coord parsing) to a
// throwaway server on 127.0.0.1; nothing here touches the network or a
// real forge.
//
// Token-resolution precedence, decided here and documented on
// `resolveGiteaToken`: a per-host token stored in settings WINS; the
// GITEA_TOKEN env var is only the fallback for a host with no stored
// token.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/gitea_api.dart';
import 'package:git_desktop/backend/remote_issue_provider.dart';
import 'package:git_desktop/backend/remote_types.dart';
import 'package:git_desktop/backend/settings_store.dart';

/// A minimal fake forge: routes are a map from `'METHOD /path'` to a
/// responder that writes the reply. Every request is counted by route so
/// tests can assert e.g. that `/labels` was fetched exactly once.
class FakeForge {
  late final HttpServer _server;
  final Map<String, int> hits = {};
  final void Function(HttpRequest req, String key) _handle;

  FakeForge(this._handle);

  static Future<FakeForge> start(
      void Function(HttpRequest req, String key) handle) async {
    final forge = FakeForge(handle);
    forge._server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    forge._server.listen((req) {
      final key = '${req.method} ${req.uri.path}';
      forge.hits[key] = (forge.hits[key] ?? 0) + 1;
      forge._handle(req, key);
    });
    return forge;
  }

  int get port => _server.port;
  String get origin => 'http://127.0.0.1:$port';
  String get apiBase => '$origin/api/v1';

  Future<void> stop() => _server.close(force: true);
}

void _json(HttpRequest req, int status, Object body) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(body));
  req.response.close();
}

/// A temp git repo whose `origin` points at [remoteUrl], so the
/// repoPath-based API surface can resolve coords the way it does in
/// production.
Future<Directory> _repoWithOrigin(String remoteUrl) async {
  final dir = await Directory.systemTemp.createTemp('gitea_test_');
  Future<void> git(List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: dir.path);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
    }
  }

  await git(['init']);
  await git(['remote', 'add', 'origin', remoteUrl]);
  return dir;
}

void main() {
  setUp(() {
    // Deterministic baseline: no stored tokens, cleared caches.
    SettingsStore.seedForTest(AppSettingsSnapshot.defaults());
    clearGiteaLabelCache();
    clearForgeProbeCache();
  });

  group('coord parsing carries scheme + port', () {
    test('http remote on a custom port keeps http and the port', () {
      final c = GiteaRepoCoords.parse(
          'http://127.0.0.1:3000/owner/repo.git');
      expect(c, isNotNull);
      expect(c!.apiBase, 'http://127.0.0.1:3000/api/v1');
      expect(c.owner, 'owner');
      expect(c.repo, 'repo');
    });

    test('ssh scp-style remote defaults to https, no port', () {
      final c = GiteaRepoCoords.parse('git@codeberg.org:owner/repo.git');
      expect(c!.apiBase, 'https://codeberg.org/api/v1');
    });

    test('ssh:// remote with explicit port drops it — SSH port is not the HTTP port', () {
      final c = GiteaRepoCoords.parse('ssh://git@gitea.corp:2222/owner/repo.git');
      expect(c, isNotNull);
      expect(c!.apiBase, 'https://gitea.corp/api/v1');
      expect(c.owner, 'owner');
      expect(c.repo, 'repo');
    });

    test('hostAndPortOfRemote reports ports for http(s) only', () {
      expect(hostAndPortOfRemote('https://gitea.corp:3000/o/r.git').port, 3000);
      expect(hostAndPortOfRemote('ssh://git@gitea.corp:2222/o/r.git').port, isNull);
      expect(hostAndPortOfRemote('ssh://git@gitea.corp:2222/o/r.git').host, 'gitea.corp');
      expect(hostAndPortOfRemote('git@gitea.corp:o/r.git').port, isNull);
    });
  });

  group('anonymous read fallback', () {
    test('stale token on a public read retries anonymously and wins', () async {
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v1/repos/o/r/issues') {
          final auth = req.headers.value('Authorization');
          if (auth != null) {
            _json(req, 401, {'message': 'token is required'});
          } else {
            _json(req, 200, [
              {'number': 1, 'title': 'public', 'state': 'open'}
            ]);
          }
          return;
        }
        _json(req, 404, {'message': 'not found'});
      });
      try {
        final r = await giteaGet(forge.apiBase, '/repos/o/r/issues',
            token: 'stale-token');
        expect(r.statusCode, 200);
        expect(r.body, contains('public'));
        expect(forge.hits['GET /api/v1/repos/o/r/issues'], 2);
      } finally {
        await forge.stop();
      }
    });

    test('private content keeps the original 401, not the anonymous echo', () async {
      final forge = await FakeForge.start((req, key) {
        _json(req, 401, {'message': 'token is required'});
      });
      try {
        final r = await giteaGet(forge.apiBase, '/repos/o/private/issues',
            token: 'stale-token');
        expect(r.statusCode, 401);
      } finally {
        await forge.stop();
      }
    });

    test('tokenless 401 does not retry', () async {
      final forge = await FakeForge.start((req, key) {
        _json(req, 401, {'message': 'auth required'});
      });
      try {
        final r = await giteaGet(forge.apiBase, '/user');
        expect(r.statusCode, 401);
        expect(forge.hits['GET /user'] ?? forge.hits.values.first, 1);
      } finally {
        await forge.stop();
      }
    });
  });

  group('token validation', () {
    test('valid token → authenticated with login', () async {
      final forge = await FakeForge.start((req, key) {
        switch (key) {
          case 'GET /api/v1/version':
            _json(req, 200, {'version': '1.22.0'});
          case 'GET /api/v1/user':
            final auth = req.headers.value('authorization');
            if (auth == 'token good') {
              _json(req, 200, {'login': 'octo'});
            } else {
              _json(req, 401, {'message': 'unauthorized'});
            }
          default:
            _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);

      final s = await giteaApiStatus(forge.apiBase, token: 'good');
      expect(s.reachable, isTrue);
      expect(s.authenticated, isTrue);
      expect(s.login, 'octo');
      expect(s.version, '1.22.0');
    });

    test('present-but-rejected token → reachable, NOT authenticated', () async {
      final forge = await FakeForge.start((req, key) {
        switch (key) {
          case 'GET /api/v1/version':
            _json(req, 200, {'version': '1.22.0'});
          case 'GET /api/v1/user':
            _json(req, 401, {'message': 'unauthorized'});
          default:
            _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);

      final s = await giteaApiStatus(forge.apiBase, token: 'bad');
      expect(s.reachable, isTrue);
      expect(s.authenticated, isFalse);
      expect(s.reason, contains('401'));
    });

    test('no server → unreachable, never authenticated', () async {
      // Bind then immediately release the port so the connect is refused.
      final tmp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dead = 'http://127.0.0.1:${tmp.port}/api/v1';
      await tmp.close(force: true);

      final s = await giteaApiStatus(dead, token: 'whatever');
      expect(s.reachable, isFalse);
      expect(s.authenticated, isFalse);
    });
  });

  group('token precedence', () {
    test('stored per-host token wins; env is the fallback', () async {
      const apiBase = 'https://git.example.com/api/v1';
      // Stored token for the host → returned regardless of env.
      SettingsStore.seedForTest(AppSettingsSnapshot.defaults()
          .copyWith(giteaTokens: {'git.example.com': 'stored-tok'}));
      expect(resolveGiteaToken(apiBase), 'stored-tok');

      // No stored token for the host → falls through to env (whatever the
      // ambient GITEA_TOKEN is, including null in a clean environment).
      SettingsStore.seedForTest(AppSettingsSnapshot.defaults());
      expect(resolveGiteaToken(apiBase),
          Platform.environment['GITEA_TOKEN']);
    });
  });

  group('labels — add + remove round trip, cached resolution', () {
    test('add then remove hits /labels exactly once', () async {
      final deleted = <String>[];
      final forge = await FakeForge.start((req, key) {
        switch (key) {
          case 'GET /api/v1/repos/owner/repo/labels':
            _json(req, 200, [
              {'id': 7, 'name': 'bug'},
              {'id': 8, 'name': 'wip'},
            ]);
          case 'POST /api/v1/repos/owner/repo/issues/1/labels':
            _json(req, 200, []);
          case 'DELETE /api/v1/repos/owner/repo/issues/1/labels/7':
            deleted.add('7');
            req.response.statusCode = 204;
            req.response.close();
          default:
            _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin(
          '${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final add =
          await addGiteaIssueLabel(repo.path, 1, 'bug', token: 'good');
      expect(add.ok, isTrue);
      final rm =
          await removeGiteaIssueLabel(repo.path, 1, 'bug', token: 'good');
      expect(rm.ok, isTrue);

      expect(deleted, ['7']);
      // The second call reused the memoised name→id map — one fetch total.
      expect(forge.hits['GET /api/v1/repos/owner/repo/labels'], 1);
    });

    test('removing an undefined label is a no-op success', () async {
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v1/repos/owner/repo/labels') {
          _json(req, 200, [
            {'id': 7, 'name': 'bug'},
          ]);
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final rm = await removeGiteaIssueLabel(repo.path, 1, 'ghost',
          token: 'good');
      expect(rm.ok, isTrue);
    });
  });

  group('CI checks — combined statuses ∪ Actions', () {
    test('unions commit statuses with Actions runs for the head', () async {
      final forge = await FakeForge.start((req, key) {
        switch (key) {
          case 'GET /api/v1/repos/owner/repo/pulls/1':
            _json(req, 200, {
              'head': {'sha': 'abc123'}
            });
          case 'GET /api/v1/repos/owner/repo/commits/abc123/status':
            _json(req, 200, {
              'state': 'success',
              'sha': 'abc123',
              'total_count': 1,
              'statuses': [
                {'context': 'lint', 'status': 'success'},
              ],
            });
          case 'GET /api/v1/repos/owner/repo/actions/tasks':
            _json(req, 200, {
              'total_count': 2,
              'workflow_runs': [
                {'name': 'build', 'status': 'running', 'head_sha': 'abc123'},
                // Different head — must be filtered out.
                {'name': 'stale', 'status': 'failure', 'head_sha': 'zzz'},
              ],
            });
          default:
            _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final r = await listGiteaCommitStatuses(repo.path, 1, token: 'good');
      expect(r.ok, isTrue);
      final names = r.data!.map((c) => c.name).toList();
      expect(names, containsAll(<String>['lint', 'build']));
      expect(names, isNot(contains('stale')));
      final build = r.data!.firstWhere((c) => c.name == 'build');
      expect(build.status, 'in_progress');
    });

    test('Actions endpoint 404 degrades silently to statuses', () async {
      final forge = await FakeForge.start((req, key) {
        switch (key) {
          case 'GET /api/v1/repos/owner/repo/pulls/1':
            _json(req, 200, {
              'head': {'sha': 'abc123'}
            });
          case 'GET /api/v1/repos/owner/repo/commits/abc123/status':
            _json(req, 200, {
              'statuses': [
                {'context': 'lint', 'status': 'success'},
              ],
            });
          // No /actions/tasks route → 404.
          default:
            _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final r = await listGiteaCommitStatuses(repo.path, 1, token: 'good');
      expect(r.ok, isTrue);
      expect(r.data!.map((c) => c.name), ['lint']);
    });
  });

  group('rate-limit courtesy', () {
    test('one 429 with Retry-After is retried exactly once', () async {
      var calls = 0;
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v1/limited') {
          calls++;
          if (calls == 1) {
            req.response.statusCode = 429;
            req.response.headers.set(HttpHeaders.retryAfterHeader, '1');
            req.response.write('{"message":"slow down"}');
            req.response.close();
          } else {
            _json(req, 200, {'ok': true});
          }
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);

      final sw = Stopwatch()..start();
      final r = await giteaGet(forge.apiBase, '/limited');
      sw.stop();

      expect(r.statusCode, 200);
      expect(calls, 2);
      // Retry-After: 1 was honoured (waited ~1s), and capped well under 5s.
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(900));
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('a persistent 429 fails after the single retry', () async {
      var calls = 0;
      final forge = await FakeForge.start((req, key) {
        calls++;
        req.response.statusCode = 429;
        req.response.write('{"message":"rate limited"}');
        req.response.close();
      });
      addTearDown(forge.stop);

      final r = await giteaGet(forge.apiBase, '/always');
      expect(r.statusCode, 429);
      expect(calls, 2); // original + one retry, no storm
    });
  });

  group('GiteaIssueProvider.status — repo-scoped readability', () {
    // `available` promises repo-scoped readability, so the unauthenticated
    // path probes /repos/owner/repo itself rather than trusting host-level
    // reachability. A private repo answers 404 anonymously and must NOT be
    // advertised as available.
    const provider = GiteaIssueProvider();

    test('reachable host, no token, repo 200 → available, no write', () async {
      final forge = await FakeForge.start((req, key) {
        switch (key) {
          case 'GET /api/v1/version':
            _json(req, 200, {'version': '1.22.0'});
          case 'GET /api/v1/repos/owner/repo':
            _json(req, 200, {'name': 'repo', 'private': false});
          default:
            _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final st = await provider.status(repo.path);
      expect(st.available, isTrue);
      expect(st.canWrite, isFalse);
    });

    test('reachable host, no token, repo 404 → unavailable', () async {
      final forge = await FakeForge.start((req, key) {
        switch (key) {
          case 'GET /api/v1/version':
            _json(req, 200, {'version': '1.22.0'});
          // Private repo hides its existence from anonymous callers.
          default:
            _json(req, 404, {'message': 'not found'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final st = await provider.status(repo.path);
      expect(st.available, isFalse);
      expect(st.reason, contains('not readable'));
    });

    test('rejected token but repo readable anonymously → available, no write',
        () async {
      // A stale stored token: /user 401s (not authenticated), yet the repo
      // read succeeds once giteaGet retries anonymously.
      final forge = await FakeForge.start((req, key) {
        final auth = req.headers.value('authorization');
        switch (key) {
          case 'GET /api/v1/version':
            _json(req, 200, {'version': '1.22.0'});
          case 'GET /api/v1/user':
            _json(req, 401, {'message': 'unauthorized'});
          case 'GET /api/v1/repos/owner/repo':
            if (auth != null) {
              _json(req, 401, {'message': 'token is required'});
            } else {
              _json(req, 200, {'name': 'repo', 'private': false});
            }
          default:
            _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      // Store the stale token for this forge's host so it's resolved. The
      // forge is on a non-default port, so the key carries `host:port`.
      SettingsStore.seedForTest(AppSettingsSnapshot.defaults()
          .copyWith(giteaTokens: {'127.0.0.1:${forge.port}': 'stale-token'}));
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final st = await provider.status(repo.path);
      expect(st.available, isTrue);
      expect(st.canWrite, isFalse);
    });
  });

  group('self-hosted forge fingerprinting (custom port)', () {
    test('Gitea /api/v1/version → gitea', () async {
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v1/version') {
          _json(req, 200, {'version': '1.22.0'});
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final f = await probeForgeForTest('${forge.origin}/owner/repo.git');
      expect(f, RemoteForge.gitea);
    });

    test('GitLab /api/v4/version 401 → gitlab', () async {
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v4/version') {
          _json(req, 401, {'message': '401 Unauthorized'});
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final f = await probeForgeForTest('${forge.origin}/owner/repo.git');
      expect(f, RemoteForge.gitlab);
    });

    test('GHE /api/v3/meta → github', () async {
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v3/meta') {
          _json(req, 200, {
            'installed_version': '3.12.0',
            'verifiable_password_authentication': true,
          });
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final f = await probeForgeForTest('${forge.origin}/owner/repo.git');
      expect(f, RemoteForge.github);
    });

    test('a plain server is unknown', () async {
      final forge = await FakeForge.start((req, key) {
        _json(req, 404, {'message': 'no'});
      });
      addTearDown(forge.stop);
      final f = await probeForgeForTest('${forge.origin}/owner/repo.git');
      expect(f, RemoteForge.unknown);
    });
  });
}
