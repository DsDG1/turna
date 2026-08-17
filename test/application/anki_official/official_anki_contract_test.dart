import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_ffi.dart';

void main() {
  final fixtures = Directory('native/turna_anki_core/contract/fixtures');

  test('decodes the shipped ENGINE_INFO golden envelope', () {
    final jsonText = File(
      '${fixtures.path}/response_engine_info.json',
    ).readAsStringSync();
    final response = OfficialAnkiEnvelopeResponse.decode(utf8.encode(jsonText));
    expect(response.ok, isTrue);
    expect(response.engine.backendCommit, isNotEmpty);
    expect(response.engine.backendCommit, isNot('hardcoded-dart'));
    expect(response.payload?['backendCommit'], response.engine.backendCommit);
    expect(response.payload?['capabilities'], contains('IMPORT_PACKAGE'));
  });

  test('encodes a v1 request matching the golden shape', () {
    final request = OfficialAnkiEnvelopeRequest(
      requestId: '01JENGINEINFO',
      operation: OfficialAnkiOperation.engineInfo,
    );
    final encoded = request.toJson();
    final golden = jsonDecode(
      File('${fixtures.path}/request_engine_info.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(encoded['contractVersion'], golden['contractVersion']);
    expect(encoded['operation'], golden['operation']);
  });

  test('rejects an unknown contract major on decode', () {
    expect(
      () => OfficialAnkiEnvelopeResponse.fromJson({
        'contractVersion': {'major': 2, 'minor': 0},
        'requestId': 'x',
        'ok': false,
        'engine': {
          'abiVersion': 1,
          'backendCommit': 'abc',
          'contractMajor': 2,
          'contractMinor': 0,
        },
        'durationMillis': 0,
      }),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.code,
          'code',
          OfficialAnkiErrorCode.contractVersionMismatch,
        ),
      ),
    );
  });

  test('ignores unknown response fields', () {
    final decoded = OfficialAnkiEnvelopeResponse.fromJson({
      'contractVersion': {'major': 1, 'minor': 0},
      'requestId': 'x',
      'ok': true,
      'payload': {'backendCommit': '967aa0d578fc75181e292e95326f9b58698da25c'},
      'error': null,
      'engine': {
        'abiVersion': 1,
        'backendCommit': '967aa0d578fc75181e292e95326f9b58698da25c',
        'contractMajor': 1,
        'contractMinor': 0,
      },
      'durationMillis': 1,
      'futureField': 'ignore',
    });
    expect(decoded.ok, isTrue);
    expect(decoded.engine.contractMajor, 1);
  });

  test('FFI engine uses the envelope payload for ENGINE_INFO', () async {
    final engine = FfiOfficialAnkiEngine(
      nativeCall: ({required operationId, required request}) {
        expect(operationId, OfficialAnkiOperation.engineInfoId);
        expect(request.operation, OfficialAnkiOperation.engineInfo);
        return OfficialAnkiEnvelopeResponse.fromJson({
          'contractVersion': {'major': 1, 'minor': 0},
          'requestId': request.requestId,
          'ok': true,
          'payload': {
            'abiVersion': 1,
            'backendCommit': '967aa0d578fc75181e292e95326f9b58698da25c',
            'contractMajor': 1,
            'contractMinor': 0,
            'capabilities': ['ENGINE_INFO', 'IMPORT_PACKAGE'],
          },
          'engine': {
            'abiVersion': 1,
            'backendCommit': '967aa0d578fc75181e292e95326f9b58698da25c',
            'contractMajor': 1,
            'contractMinor': 0,
          },
          'durationMillis': 2,
        });
      },
    );
    final info = await engine.engineInfo();
    expect(info.backendCommit, '967aa0d578fc75181e292e95326f9b58698da25c');
    expect(info.has('IMPORT_PACKAGE'), isTrue);
  });

  test('1.1 client ignores unknown 1.2 capabilities', () {
    final info = OfficialAnkiEngineInfo.fromJson({
      'abiVersion': 1,
      'backendCommit': '967aa0d578fc75181e292e95326f9b58698da25c',
      'contractMajor': 1,
      'contractMinor': 2,
      'capabilities': [
        'ENGINE_INFO',
        'GET_PROJECTION_SCHEMAS',
        'BEGIN_PROJECTION_READ',
        'GET_PROJECTION_ROWS_BATCH',
        'FUTURE_OP',
      ],
    });
    expect(info.contractMinor, 2);
    expect(info.has('GET_PROJECTION_SCHEMAS'), isTrue);
    expect(info.has('FUTURE_OP'), isTrue);
    expect(
      () => OfficialAnkiOperation.idFor('FUTURE_OP'),
      throwsA(isA<OfficialAnkiException>()),
    );
    expect(
      OfficialAnkiOperation.idFor(OfficialAnkiOperation.getProjectionSchemas),
      OfficialAnkiOperation.getProjectionSchemasId,
    );
  });

  test('archived proto is not the wire truth', () {
    expect(
      File('native/turna_anki_core/contract/turna_anki_spike.proto').existsSync(),
      isFalse,
    );
    expect(
      File(
        'native/turna_anki_core/contract/archive/turna_anki_spike.proto',
      ).existsSync(),
      isTrue,
    );
  });
}
