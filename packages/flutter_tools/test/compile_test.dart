// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/compile.dart';
import 'package:mockito/mockito.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';

import 'src/context.dart';

void main() {
  group('batch compile', () {
    ProcessManager mockProcessManager;
    MockProcess mockFrontendServer;
    MockStdIn mockFrontendServerStdIn;
    MockStream mockFrontendServerStdErr;
    setUp(() {
      mockProcessManager = new MockProcessManager();
      mockFrontendServer = new MockProcess();
      mockFrontendServerStdIn = new MockStdIn();
      mockFrontendServerStdErr = new MockStream();

      when(mockFrontendServer.stderr).thenReturn(mockFrontendServerStdErr);
      final StreamController<String> stdErrStreamController = new StreamController<String>();
      when(mockFrontendServerStdErr.transform<String>(any)).thenReturn(stdErrStreamController.stream);
      when(mockFrontendServer.stdin).thenReturn(mockFrontendServerStdIn);
      when(mockProcessManager.start(any)).thenReturn(new Future<Process>.value(mockFrontendServer));
      when(mockFrontendServer.exitCode).thenReturn(0);
    });

    testUsingContext('single dart successful compilation', () async {
      final BufferLogger logger = context[Logger];
      when(mockFrontendServer.stdout).thenReturn(new Stream<List<int>>.fromFuture(
        new Future<List<int>>.value(UTF8.encode(
          'result abc\nline1\nline2\nabc /path/to/main.dart.dill'
        ))
      ));
      final String output = await compile(sdkRoot: '/path/to/sdkroot',
        mainPath: '/path/to/main.dart'
      );
      verifyNever(mockFrontendServerStdIn.writeln(any));
      expect(logger.traceText, equals('compile debug message: line1\ncompile debug message: line2\n'));
      expect(output, equals('/path/to/main.dart.dill'));
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });

    testUsingContext('single dart failed compilation', () async {
      final BufferLogger logger = context[Logger];

      when(mockFrontendServer.stdout).thenReturn(new Stream<List<int>>.fromFuture(
        new Future<List<int>>.value(UTF8.encode(
          'result abc\nline1\nline2\nabc'
        ))
      ));

      final String output = await compile(sdkRoot: '/path/to/sdkroot',
        mainPath: '/path/to/main.dart'
      );
      verifyNever(mockFrontendServerStdIn.writeln(any));
      expect(logger.traceText, equals('compile debug message: line1\ncompile debug message: line2\n'));
      expect(output, equals(null));
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });
  });

  group('incremental compile', () {
    ProcessManager mockProcessManager;
    ResidentCompiler generator;
    MockProcess mockFrontendServer;
    MockStdIn mockFrontendServerStdIn;
    MockStream mockFrontendServerStdErr;
    StreamController<String> stdErrStreamController;

    setUp(() {
      generator = new ResidentCompiler('sdkroot');
      mockProcessManager = new MockProcessManager();
      mockFrontendServer = new MockProcess();
      mockFrontendServerStdIn = new MockStdIn();
      mockFrontendServerStdErr = new MockStream();

      when(mockFrontendServer.stdin).thenReturn(mockFrontendServerStdIn);
      when(mockFrontendServer.stderr).thenReturn(mockFrontendServerStdErr);
      stdErrStreamController = new StreamController<String>();
      when(mockFrontendServerStdErr.transform<String>(any)).thenReturn(stdErrStreamController.stream);

      when(mockProcessManager.start(any)).thenReturn(
          new Future<Process>.value(mockFrontendServer)
      );
      when(mockFrontendServer.exitCode).thenReturn(0);
    });

    testUsingContext('single dart compile', () async {
      final BufferLogger logger = context[Logger];

      when(mockFrontendServer.stdout).thenReturn(new Stream<List<int>>.fromFuture(
        new Future<List<int>>.value(UTF8.encode(
          'result abc\nline1\nline2\nabc /path/to/main.dart.dill'
        ))
      ));

      final String output = await generator.recompile(
        '/path/to/main.dart', null /* invalidatedFiles */
      );
      verify(mockFrontendServerStdIn.writeln('compile /path/to/main.dart'));
      verifyNoMoreInteractions(mockFrontendServerStdIn);
      expect(logger.traceText, equals('compile debug message: line1\ncompile debug message: line2\n'));
      expect(output, equals('/path/to/main.dart.dill'));
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });

    testUsingContext('compile and recompile', () async {
      final BufferLogger logger = context[Logger];

      when(mockFrontendServer.stdout).thenReturn(new Stream<List<int>>.fromFuture(
        new Future<List<int>>.value(UTF8.encode(
          'result abc\nline1\nline2\nabc /path/to/main.dart.dill'
        ))
      ));

      await generator.recompile('/path/to/main.dart', null /* invalidatedFiles */);
      verify(mockFrontendServerStdIn.writeln('compile /path/to/main.dart'));

      final String output = await generator.recompile(
        null /* mainPath */,
        <String>['/path/to/main.dart']
      );
      final String recompileCommand = verify(mockFrontendServerStdIn.writeln(captureThat(startsWith('recompile ')))).captured[0];
      final String token = recompileCommand.split(' ')[1];
      verify(mockFrontendServerStdIn.writeln('/path/to/main.dart'));
      verify(mockFrontendServerStdIn.writeln(token));
      verifyNoMoreInteractions(mockFrontendServerStdIn);
      expect(logger.traceText, equals('compile debug message: line1\ncompile debug message: line2\n'));
      expect(output, equals('/path/to/main.dart.dill'));
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });
  });
}

class MockProcessManager extends Mock implements ProcessManager {}
class MockProcess extends Mock implements Process {}
class MockStream extends Mock implements Stream<List<int>> {}
class MockStdIn extends Mock implements IOSink {}
