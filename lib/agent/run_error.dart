import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/agent/model_refusal.dart';
import 'package:skapie/agent/run_control.dart';

enum RunErrorKind {
  authentication,
  rateLimit,
  timeout,
  invalidToolSchema,
  contextLimit,
  transport,
  modelRefusal,
  limit,
  engine,
}

RunErrorKind classifyRunError(Object error) {
  if (error is ModelRefusalException) return RunErrorKind.modelRefusal;
  if (error is RunLimitReached) return RunErrorKind.limit;
  if (error is TimeoutException) return RunErrorKind.timeout;
  if (error is SocketException ||
      error is HttpException ||
      error is http.ClientException) {
    return RunErrorKind.transport;
  }
  if (error is AgentHttpException) {
    final status = error.statusCode;
    if (status == 401 || status == 403) return RunErrorKind.authentication;
    if (status == 429) return RunErrorKind.rateLimit;
    final description = '${error.message} ${error.body ?? ''}'.toLowerCase();
    if (description.contains('timed out') || status == 408 || status == 504) {
      return RunErrorKind.timeout;
    }
    if (description.contains('context') ||
        description.contains('maximum tokens') ||
        description.contains('token limit')) {
      return RunErrorKind.contextLimit;
    }
    if (description.contains('tool') &&
        (description.contains('schema') || description.contains('function'))) {
      return RunErrorKind.invalidToolSchema;
    }
    if (description.contains('refus') || description.contains('safety')) {
      return RunErrorKind.modelRefusal;
    }
    if (status == null || status >= 500) return RunErrorKind.transport;
  }
  return RunErrorKind.engine;
}

String runErrorLabel(RunErrorKind kind) => switch (kind) {
  RunErrorKind.authentication => 'Check provider sign in or API key',
  RunErrorKind.rateLimit => 'Provider rate limit reached',
  RunErrorKind.timeout => 'Request timed out',
  RunErrorKind.invalidToolSchema => 'A connected tool schema was rejected',
  RunErrorKind.contextLimit => 'Model context limit reached',
  RunErrorKind.transport => 'Connection to provider failed',
  RunErrorKind.modelRefusal => 'Model declined this request',
  RunErrorKind.limit => 'Run limit reached',
  RunErrorKind.engine => 'Run failed',
};
