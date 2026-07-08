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
import 'package:git_desktop/backend/git_result.dart';
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
  req.response.headers.contentType =
      ContentType('application', 'json', charset: 'utf-8');
  // Emit UTF-8 bytes explicitly. `HttpResponse.write` would encode through
  // the sink's default encoding, which mangles multi-byte characters (emoji,
  // RTL, CJK) — and the production client always decodes with utf8.decoder,
  // so the fake must speak the same charset or the round-trip is lossy.
  req.response.add(utf8.encode(jsonEncode(body)));
  req.response.close();
}

/// Write an arbitrary (possibly non-JSON / malformed) body verbatim with a
/// chosen status. Used to probe the client's tolerance of garbage responses.
void _raw(HttpRequest req, int status, String body) {
  req.response.statusCode = status;
  req.response.add(utf8.encode(body));
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

  // -------------------------------------------------------------------------
  // Malformed responses — every list*/get*/create* parser must return a
  // GitResult.err (or a documented safe default) rather than throw. A single
  // reconfigurable forge + repo drives the whole table so the suite doesn't
  // stand up a server per case.
  // -------------------------------------------------------------------------
  group('malformed responses — parsers never throw', () {
    late FakeForge forge;
    late Directory repo;
    var raw = '';
    var getStatus = 200;

    setUpAll(() async {
      forge = await FakeForge.start((req, key) {
        // GETs answer [getStatus]; POSTs answer 201 so create* reaches its
        // response parse. Either way the (possibly garbage) [raw] body is
        // returned verbatim.
        _raw(req, req.method == 'GET' ? getStatus : 201, raw);
      });
      repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
    });
    tearDownAll(() async {
      await forge.stop();
      await repo.delete(recursive: true);
    });

    // Each function that decodes a JSON body. `giteaWhoami`,
    // `listGiteaCommitStatuses` and the label calls have their own tests
    // below (safe-default string / multi-step flows).
    final parsers = <String, Future<GitResult<Object?>> Function()>{
      'listGiteaPulls': () => listGiteaPulls(repo.path, token: 'good'),
      'getGiteaPull': () => getGiteaPull(repo.path, 1, token: 'good'),
      'giteaPullDetail': () =>
          giteaPullDetail(repo.path, 1, includeDiff: false, token: 'good'),
      'listGiteaIssues': () => listGiteaIssues(repo.path, token: 'good'),
      'getGiteaIssue': () => getGiteaIssue(repo.path, 1, token: 'good'),
      'giteaIssueDetail': () => giteaIssueDetail(repo.path, 1, token: 'good'),
      'createGiteaIssue': () =>
          createGiteaIssue(repo.path, title: 't', token: 'good'),
      'createGiteaPull': () => createGiteaPull(repo.path,
          title: 't', headRef: 'feat', baseRef: 'main', token: 'good'),
    };

    for (final entry in parsers.entries) {
      test('${entry.key}: invalid JSON body → err, no throw', () async {
        raw = 'not json{{{';
        getStatus = 200;
        final r = await entry.value();
        expect(r.ok, isFalse, reason: '${entry.key} must not succeed on garbage');
        expect(r.error, isNotNull);
      });

      test('${entry.key}: empty body 200 → err, no throw', () async {
        raw = '';
        getStatus = 200;
        final r = await entry.value();
        expect(r.ok, isFalse);
      });
    }

    test('wrong shape: object where a list is expected (listGiteaIssues)',
        () async {
      raw = '{"not":"a list"}';
      getStatus = 200;
      final r = await listGiteaIssues(repo.path, token: 'good');
      expect(r.ok, isFalse);
    });

    test('wrong shape: list where an object is expected (getGiteaIssue)',
        () async {
      raw = '[1,2,3]';
      getStatus = 200;
      final r = await getGiteaIssue(repo.path, 1, token: 'good');
      expect(r.ok, isFalse);
    });

    test('required field missing: issue object without `number`', () async {
      raw = '{"title":"no number"}';
      getStatus = 200;
      final r = await getGiteaIssue(repo.path, 1, token: 'good');
      expect(r.ok, isFalse);
    });

    test('null in a non-null field: number explicitly null', () async {
      raw = '{"number":null,"title":"x"}';
      getStatus = 200;
      final r = await getGiteaIssue(repo.path, 1, token: 'good');
      expect(r.ok, isFalse);
    });

    test('list element missing required field (listGiteaPulls)', () async {
      raw = '[{"title":"nameless"}]';
      getStatus = 200;
      final r = await listGiteaPulls(repo.path, token: 'good');
      expect(r.ok, isFalse);
    });

    test('giteaWhoami degrades to empty string on invalid JSON', () async {
      raw = 'not json{{{';
      getStatus = 200;
      expect(await giteaWhoami(repo.path), isEmpty);
    });

    test('huge (~1MB) valid list body parses without choking', () async {
      final items = List.generate(
          16000,
          (i) => {
                'number': i + 1,
                'title': 'issue $i with padding text to inflate the payload',
                'state': 'open',
              });
      raw = jsonEncode(items);
      expect(raw.length, greaterThan(1024 * 1024));
      getStatus = 200;
      final r = await listGiteaIssues(repo.path, token: 'good');
      expect(r.ok, isTrue);
      // The client caps at its default limit (100) regardless of body size.
      expect(r.data!.length, 100);
    });
  });

  group('malformed responses — commit statuses', () {
    test('malformed PR body degrades to empty checks, never throws', () async {
      // Regression pin: the PR fetch that recovers the head sha jsonDecoded
      // its body UNGUARDED, so a 200 with garbage threw straight out of
      // listGiteaCommitStatuses. It must now degrade to ok([]).
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v1/repos/owner/repo/pulls/1') {
          _raw(req, 200, 'not json{{{');
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final r = await listGiteaCommitStatuses(repo.path, 1, token: 'good');
      expect(r.ok, isTrue);
      expect(r.data, isEmpty);
    });

    test('malformed combined-status body surfaces a parse error', () async {
      final forge = await FakeForge.start((req, key) {
        switch (key) {
          case 'GET /api/v1/repos/owner/repo/pulls/1':
            _json(req, 200, {
              'head': {'sha': 'abc123'}
            });
          case 'GET /api/v1/repos/owner/repo/commits/abc123/status':
            _raw(req, 200, 'not json{{{');
          default:
            _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final r = await listGiteaCommitStatuses(repo.path, 1, token: 'good');
      expect(r.ok, isFalse);
      expect(r.error, contains('parse commit statuses'));
    });
  });

  group('malformed responses — label resolution', () {
    // Regression pin: `_resolveLabelIds` jsonDecoded /labels UNGUARDED, so a
    // garbage body threw out of every label-touching caller.
    test('addGiteaIssueLabel → "could not fetch labels" on garbage /labels',
        () async {
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v1/repos/owner/repo/labels') {
          _raw(req, 200, 'not json{{{');
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final r = await addGiteaIssueLabel(repo.path, 1, 'bug', token: 'good');
      expect(r.ok, isFalse);
      expect(r.error, contains('fetch labels'));
    });

    test('removeGiteaIssueLabel surfaces the fetch failure on garbage /labels',
        () async {
      // Distinct from the "undefined label on a healthy repo" no-op: when the
      // /labels fetch itself yields garbage, the map is unresolvable and the
      // call must fail cleanly (not throw, not silently succeed).
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v1/repos/owner/repo/labels') {
          _raw(req, 200, '{"unexpected":"object not a list"}');
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final r = await removeGiteaIssueLabel(repo.path, 1, 'bug', token: 'good');
      expect(r.ok, isFalse);
      expect(r.error, contains('fetch labels'));
    });

    test('removeGiteaIssueLabel no-ops when the label is simply undefined',
        () async {
      // The genuine safe-default path: /labels parses fine but doesn't define
      // the requested label → nothing to remove → success.
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

      final r =
          await removeGiteaIssueLabel(repo.path, 1, 'ghost', token: 'good');
      expect(r.ok, isTrue);
    });

    test('label object with a null id does not throw (unresolvable)', () async {
      final forge = await FakeForge.start((req, key) {
        if (key == 'GET /api/v1/repos/owner/repo/labels') {
          _json(req, 200, [
            {'name': 'bug'}, // id missing → `l['id'] as num` would throw
          ]);
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/owner/repo.git');
      addTearDown(() => repo.delete(recursive: true));

      final r = await addGiteaIssueLabel(repo.path, 1, 'bug', token: 'good');
      expect(r.ok, isFalse);
      expect(r.error, contains('fetch labels'));
    });
  });

  // -------------------------------------------------------------------------
  // Transport nastiness — the client must surface an error or complete
  // boundedly, never throw uncaught or hang forever.
  // -------------------------------------------------------------------------
  group('transport nastiness', () {
    test('connection closed mid-body → sentinel status 0, no throw', () async {
      final forge = await FakeForge.start((req, key) async {
        // Promise a long body via Content-Length, send a fragment, then kill
        // the socket so the client sees an abrupt close mid-body.
        final socket = await req.response.detachSocket(writeHeaders: false);
        socket.write('HTTP/1.1 200 OK\r\n'
            'Content-Type: application/json\r\n'
            'Content-Length: 4096\r\n\r\n'
            '{"partial":');
        await socket.flush();
        socket.destroy();
      });
      addTearDown(forge.stop);

      final r = await giteaGet(forge.apiBase, '/repos/o/r/issues', token: 't');
      // A thrown/aborted request is mapped to the sentinel status 0.
      expect(r.statusCode, 0);
    });

    test('a 2s-delayed response completes without hanging', () async {
      final forge = await FakeForge.start((req, key) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        _json(req, 200, {'ok': true});
      });
      addTearDown(forge.stop);

      final sw = Stopwatch()..start();
      final r = await giteaGet(forge.apiBase, '/slow');
      sw.stop();
      expect(r.statusCode, 200);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(1900));
      expect(sw.elapsedMilliseconds, lessThan(10000));
    });

    test('a plain 500 is not auto-retried; a manual retry then succeeds',
        () async {
      var calls = 0;
      final forge = await FakeForge.start((req, key) {
        calls++;
        if (calls == 1) {
          _json(req, 500, {'message': 'boom'});
        } else {
          _json(req, 200, {'ok': true});
        }
      });
      addTearDown(forge.stop);

      final first = await giteaGet(forge.apiBase, '/flaky', token: 't');
      expect(first.statusCode, 500);
      expect(calls, 1); // exactly one request — no retry storm on a plain 500

      final second = await giteaGet(forge.apiBase, '/flaky', token: 't');
      expect(second.statusCode, 200);
      expect(calls, 2);
    });

    for (final bad in const ['soon', '-5', '']) {
      final label = bad.isEmpty ? '(empty)' : '"$bad"';
      test('429 with malformed Retry-After $label → default backoff, one retry',
          () async {
        var calls = 0;
        final forge = await FakeForge.start((req, key) {
          calls++;
          if (calls == 1) {
            req.response.statusCode = 429;
            req.response.headers.set(HttpHeaders.retryAfterHeader, bad);
            req.response.write('{"message":"slow down"}');
            req.response.close();
          } else {
            _json(req, 200, {'ok': true});
          }
        });
        addTearDown(forge.stop);

        final sw = Stopwatch()..start();
        final r = await giteaGet(forge.apiBase, '/limited');
        sw.stop();
        expect(r.statusCode, 200);
        expect(calls, 2); // original + exactly one retry
        // Unparseable Retry-After falls back to the fixed 500ms backoff — it
        // must neither shortcut the wait nor storm.
        expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(400));
        expect(sw.elapsedMilliseconds, lessThan(5000));
      });
    }
  });

  // -------------------------------------------------------------------------
  // Unicode + hostile content must round-trip byte-for-byte through
  // create → list → get-detail (catches double-encoding / HTML-escaping /
  // charset mangling on either the client or the fake).
  // -------------------------------------------------------------------------
  group('unicode + hostile content round-trips', () {
    const probes = <String>[
      '👨‍👩‍👧‍👦 family', // multi-codepoint ZWJ emoji
      '🇯🇵 flag', // regional-indicator flag
      'مرحبا بالعالم', // Arabic (RTL)
      'שלום עולם', // Hebrew (RTL)
      '日本語のテスト 测试', // CJK
      "<script>alert('it\\'s xss')</script>", // quotes + angle brackets
    ];

    for (var i = 0; i < probes.length; i++) {
      final probe = probes[i];
      test('probe #$i survives create → list → get → detail', () async {
        final issues = <Map<String, dynamic>>[];
        final comments = <Map<String, dynamic>>[];
        final labelDef = [
          {'id': 1, 'name': probe}
        ];
        final forge = await FakeForge.start((req, key) async {
          switch (key) {
            case 'GET /api/v1/repos/o/r/labels':
              _json(req, 200, labelDef);
            case 'POST /api/v1/repos/o/r/issues':
              final m = jsonDecode(await utf8.decodeStream(req))
                  as Map<String, dynamic>;
              issues.add({
                'number': 1,
                'title': m['title'],
                'body': m['body'] ?? '',
                'state': 'open',
                'labels': labelDef,
                'comments': 0,
              });
              _json(req, 201, issues.first);
            case 'GET /api/v1/repos/o/r/issues':
              _json(req, 200, issues);
            case 'GET /api/v1/repos/o/r/issues/1':
              _json(req, 200, issues.first);
            case 'GET /api/v1/repos/o/r/issues/1/comments':
              _json(req, 200, comments);
            case 'POST /api/v1/repos/o/r/issues/1/comments':
              final m = jsonDecode(await utf8.decodeStream(req))
                  as Map<String, dynamic>;
              comments.add({
                'body': m['body'],
                'user': {'login': 'octo'},
                'created_at': '2024-01-01T00:00:00Z',
              });
              _json(req, 201, comments.last);
            default:
              _json(req, 404, {'message': 'no'});
          }
        });
        addTearDown(forge.stop);
        final repo = await _repoWithOrigin('${forge.origin}/o/r.git');
        addTearDown(() => repo.delete(recursive: true));

        final created = await createGiteaIssue(repo.path,
            title: probe, body: probe, labels: [probe], token: 'good');
        expect(created.ok, isTrue, reason: created.error);
        expect(created.data, 1);

        final list = await listGiteaIssues(repo.path, token: 'good');
        expect(list.ok, isTrue);
        expect(list.data!.single.title, probe);
        expect(list.data!.single.labels, [probe]);

        final got = await getGiteaIssue(repo.path, 1, token: 'good');
        expect(got.data!.title, probe);

        final commented =
            await giteaCommentOnIssue(repo.path, 1, probe, token: 'good');
        expect(commented.ok, isTrue);

        final detail = await giteaIssueDetail(repo.path, 1, token: 'good');
        expect(detail.ok, isTrue);
        expect(detail.data!.body, probe);
        expect(detail.data!.labels, [probe]);
        expect(detail.data!.comments.single.body, probe);
      });
    }
  });

  // -------------------------------------------------------------------------
  // Auth matrix — the (reachable, authenticated, reason) tuple giteaApiStatus
  // produces across {token source} × {server response}. Source precedence is
  // asserted through resolveGiteaToken; the response dimension is driven with
  // a STORED token (no explicit param) so the stored→used path runs for real.
  // -------------------------------------------------------------------------
  group('auth matrix — giteaApiStatus', () {
    Future<FakeForge> forgeWithUser(int userStatus, {String login = 'octo'}) {
      return FakeForge.start((req, key) {
        switch (key) {
          case 'GET /api/v1/version':
            _json(req, 200, {'version': '1.22.0'});
          case 'GET /api/v1/user':
            if (userStatus == 200) {
              _json(req, 200, {'login': login});
            } else {
              _json(req, userStatus, {'message': 'nope'});
            }
          default:
            _json(req, 404, {'message': 'no'});
        }
      });
    }

    void seedStored(int port, String tok) => SettingsStore.seedForTest(
        AppSettingsSnapshot.defaults()
            .copyWith(giteaTokens: {'127.0.0.1:$port': tok}));

    test('source: stored wins (both cell); neither → env value (null clean)',
        () {
      const apiBase = 'https://forge.example/api/v1';
      // Stored present → returned before env is ever consulted. This is both
      // the "stored" and the "both stored+env" cell: stored always wins.
      SettingsStore.seedForTest(AppSettingsSnapshot.defaults()
          .copyWith(giteaTokens: {'forge.example': 'stored'}));
      expect(resolveGiteaToken(apiBase), 'stored');
      // Neither stored → env fallback, which is null in a clean test env.
      SettingsStore.seedForTest(AppSettingsSnapshot.defaults());
      expect(resolveGiteaToken(apiBase), Platform.environment['GITEA_TOKEN']);
    });

    test('stored × valid /user → reachable + authenticated + login', () async {
      final forge = await forgeWithUser(200, login: 'octo');
      addTearDown(forge.stop);
      seedStored(forge.port, 'good');
      final s = await giteaApiStatus(forge.apiBase);
      expect(s.reachable, isTrue);
      expect(s.authenticated, isTrue);
      expect(s.login, 'octo');
      expect(s.reason, isNull);
    });

    test('stored × rejected /user (401) → reachable, not auth, token rejected',
        () async {
      final forge = await forgeWithUser(401);
      addTearDown(forge.stop);
      seedStored(forge.port, 'bad');
      final s = await giteaApiStatus(forge.apiBase);
      expect(s.reachable, isTrue);
      expect(s.authenticated, isFalse);
      expect(s.reason, 'token rejected (401)');
    });

    test('stored × /user 500 → reachable, not auth, token check returned 500',
        () async {
      final forge = await forgeWithUser(500);
      addTearDown(forge.stop);
      seedStored(forge.port, 'tok');
      final s = await giteaApiStatus(forge.apiBase);
      expect(s.reachable, isTrue);
      expect(s.authenticated, isFalse);
      expect(s.reason, 'token check returned 500');
    });

    test('neither token, reachable → not auth, "no token for this host"',
        () async {
      final forge = await forgeWithUser(200);
      addTearDown(forge.stop);
      // setUp already cleared stored tokens; env is unset in a clean env.
      final s = await giteaApiStatus(forge.apiBase);
      if (Platform.environment['GITEA_TOKEN'] == null) {
        expect(s.reachable, isTrue);
        expect(s.authenticated, isFalse);
        expect(s.reason, 'no token for this host');
      } else {
        // Ambient GITEA_TOKEN present → it authenticates against the fake.
        expect(s.authenticated, isTrue);
      }
    });

    test('version endpoint non-200 → unreachable with status in reason',
        () async {
      final forge = await FakeForge.start((req, key) {
        _json(req, 503, {'message': 'down'});
      });
      addTearDown(forge.stop);
      final s = await giteaApiStatus(forge.apiBase, token: 'whatever');
      expect(s.reachable, isFalse);
      expect(s.authenticated, isFalse);
      expect(s.reason, contains('503'));
    });
  });

  // -------------------------------------------------------------------------
  // Anonymous-read-fallback edge cases.
  // -------------------------------------------------------------------------
  group('anonymous read fallback — edges', () {
    test('token 401 then anonymous 403 preserves the original 401', () async {
      final forge = await FakeForge.start((req, key) {
        if (req.headers.value('authorization') != null) {
          _json(req, 401, {'message': 'token rejected'});
        } else {
          _json(req, 403, {'message': 'forbidden'});
        }
      });
      addTearDown(forge.stop);

      final r =
          await giteaGet(forge.apiBase, '/repos/o/r/issues', token: 'stale');
      // The anonymous retry's 403 is not a 2xx, so the clearer original 401
      // stands — the 403 must not leak through, nor be swallowed to 200.
      expect(r.statusCode, 401);
      expect(forge.hits['GET /api/v1/repos/o/r/issues'], 2);
    });

    test('a rejected write (POST 401) never falls back to anonymous', () async {
      final forge = await FakeForge.start((req, key) {
        if (key == 'POST /api/v1/repos/o/r/issues/1/comments') {
          _json(req, 401, {'message': 'token rejected'});
        } else {
          _json(req, 404, {'message': 'no'});
        }
      });
      addTearDown(forge.stop);
      final repo = await _repoWithOrigin('${forge.origin}/o/r.git');
      addTearDown(() => repo.delete(recursive: true));

      final r =
          await giteaCommentOnIssue(repo.path, 1, 'hello', token: 'stale');
      expect(r.ok, isFalse);
      // Exactly one request total — writes must never replay anonymously.
      expect(forge.hits['POST /api/v1/repos/o/r/issues/1/comments'], 1);
    });
  });
}
