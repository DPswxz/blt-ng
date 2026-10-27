import 'dart:async';
import 'package:dio/dio.dart';

const _requestTokenKey = #bltRequestLifetime;
CancelToken? get currentRequestToken =>
    Zone.current[_requestTokenKey] as CancelToken?;

/// Propagates page lifetime cancellation through existing API helpers.
class RequestScope {
  CancelToken _token = CancelToken();
  bool _disposed = false;
  Future<T> run<T>(Future<T> Function() request, {bool replace = false}) {
    if (_disposed) return Future.error(StateError('Request scope disposed'));
    if (replace) {
      _token.cancel('Superseded');
      _token = CancelToken();
    }
    return runZoned(request, zoneValues: {_requestTokenKey: _token});
  }

  void cancel() {
    if (_disposed) return;
    _token.cancel('Superseded');
    _token = CancelToken();
  }

  void dispose() {
    _disposed = true;
    _token.cancel('Page disposed');
  }
}
