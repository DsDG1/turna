import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/endpoint_url_policy.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';
import 'package:turna/service/remote_backup/webdav_client.dart';

/// Turna has two user-configurable network exits that both send a credential
/// on every request: the AI base URL and the WebDAV server URL. They are
/// validated by one policy, so these tests pin the *shared* behaviour — if the
/// two ever diverge again, it will be because a copy was made here.
void main() {
  group('normalize', () {
    test('accepts https and strips trailing slashes', () {
      final (:value, :problem) = EndpointUrlPolicy.normalizeForBuild(
          'https://dav.x.com//',
          debugBuild: true);

      expect(problem, isNull);
      expect(value, 'https://dav.x.com');
    });

    test('keeps a path prefix intact', () {
      final (:value, :problem) = EndpointUrlPolicy.normalizeForBuild(
          'https://cloud.x.com/remote.php/dav/',
          debugBuild: true);

      expect(problem, isNull);
      expect(value, 'https://cloud.x.com/remote.php/dav');
    });

    test('rejects an empty value', () {
      expect(
          EndpointUrlPolicy.normalizeForBuild('   ', debugBuild: true).problem,
          EndpointUrlProblem.empty);
    });

    test('rejects a scheme that is neither http nor https', () {
      for (final raw in [
        'ftp://dav.x.com',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'dav.x.com',
      ]) {
        // Build-mode independent: an unusable scheme is always a problem, in
        // debug as well, so this is not a development convenience.
        for (final debug in [true, false]) {
          expect(
            EndpointUrlPolicy.normalizeForBuild(raw, debugBuild: debug).problem,
            EndpointUrlProblem.unsupportedScheme,
            reason: '$raw (debugBuild: $debug) must not be a usable endpoint',
          );
        }
      }
    });

    test('rejects a URL with no host', () {
      expect(
        EndpointUrlPolicy.normalizeForBuild('https:///dav', debugBuild: true)
            .problem,
        EndpointUrlProblem.malformed,
      );
    });

    test('release requires https for a remote host', () {
      expect(
        EndpointUrlPolicy.normalizeForBuild('http://dav.example.com',
                debugBuild: false)
            .problem,
        EndpointUrlProblem.httpsRequired,
        reason: 'Basic auth over cleartext discloses the password in '
            'reversible base64',
      );
    });

    test('debug permits cleartext to a remote host', () {
      expect(
        EndpointUrlPolicy.normalizeForBuild('http://dav.example.com',
                debugBuild: true)
            .problem,
        isNull,
      );
    });

    test('loopback stays reachable in release too', () {
      for (final raw in [
        'http://localhost:8080/dav',
        'http://127.0.0.1:8080/dav',
        'http://[::1]:8080/dav',
        'http://0.0.0.0:8080/dav',
      ]) {
        expect(
          EndpointUrlPolicy.normalizeForBuild(raw, debugBuild: false).problem,
          isNull,
          reason: '$raw must be usable against a local server in release; '
              'loopback traffic never leaves the machine',
        );
      }
    });

    test('isLoopbackHost is case-insensitive and rejects lookalikes', () {
      expect(EndpointUrlPolicy.isLoopbackHost('LOCALHOST'), isTrue);
      expect(EndpointUrlPolicy.isLoopbackHost('[::1]'), isTrue);
      expect(EndpointUrlPolicy.isLoopbackHost('localhost.evil.com'), isFalse);
      expect(EndpointUrlPolicy.isLoopbackHost('127.0.0.1.evil.com'), isFalse);
      expect(EndpointUrlPolicy.isLoopbackHost('0.0.0.0.evil.com'), isFalse);
    });
  });

  group('RemoteBackupEndpointConfig.validateServerUrl', () {
    test('accepts a normal https endpoint', () {
      final config = RemoteBackupEndpointConfig(
        serverUrl: 'https://dav.example.com',
        username: 'u',
      );

      expect(config.validateServerUrl(), isNull);
    });

    test('rejects an unusable scheme regardless of build mode', () {
      final config =
          RemoteBackupEndpointConfig(serverUrl: 'ftp://dav.example.com');

      expect(config.validateServerUrl(), EndpointUrlProblem.unsupportedScheme);
    });
  });

  group('WebDavClient refuses to attach credentials to a bad endpoint', () {
    test('an unusable scheme throws before any socket is opened', () async {
      final client = WebDavClient(
        baseUrl: Uri.parse('ftp://dav.example.com'),
        username: 'user',
        password: 'hunter2',
      );
      addTearDown(client.close);

      // probe() is async, so the guard's throw arrives through the future —
      // it is raised inside _authorize, which runs before the request is sent.
      await expectLater(
        client.probe(),
        throwsA(isA<WebDavInsecureEndpointException>()),
      );
    });

    test('a loopback http endpoint still gets its credentials', () async {
      // The mirror of the test above: the guard must not over-block. A real
      // local server proves the request went out *with* the Authorization
      // header, which is what a permitted endpoint is supposed to do.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final authHeaders = <String?>[];
      server.listen((request) async {
        authHeaders.add(request.headers.value(HttpHeaders.authorizationHeader));
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      final client = WebDavClient(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}/dav'),
        username: 'user',
        password: 'hunter2',
      );
      addTearDown(client.close);

      await client.probe();

      expect(authHeaders, isNotEmpty);
      expect(authHeaders.single, startsWith('Basic '));
    });
  });
}
