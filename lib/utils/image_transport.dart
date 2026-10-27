import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:blt/utils/log.dart';

final _imageLog = log('image');

HttpClient createImageHttpClient() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 4)
  ..idleTimeout = const Duration(seconds: 15)
  ..maxConnectionsPerHost = 4
  ..connectionFactory = (uri, proxyHost, proxyPort) async {
    if (uri.scheme == 'https' && proxyHost == null) {
      final addresses = await InternetAddress.lookup(
        uri.host,
        type: InternetAddressType.IPv4,
      );
      // lookup preserves the DNS hostname on InternetAddress, so TLS still
      // sends the original SNI and validates the normal certificate chain.
      return SecureSocket.startConnect(addresses.first, uri.port);
    }
    return Socket.startConnect(
      proxyHost ?? uri.host,
      proxyPort ?? uri.port,
      sourceAddress: InternetAddress.anyIPv4,
    );
  };

List<Uri> imageDownloadCandidates(String url) {
  final uri = Uri.parse(url.startsWith('//') ? 'https:$url' : url);
  if (!RegExp(r'^i[012]\.hdslb\.com$').hasMatch(uri.host)) return [uri];
  final secure = uri.replace(scheme: 'https');
  if (uri.hasQuery || uri.hasFragment) return [secure];
  return [
    secure,
    for (final host in ['i0.hdslb.com', 'i1.hdslb.com', 'i2.hdslb.com'])
      if (host != secure.host) secure.replace(host: host),
  ];
}

/// Shares the cache manager's four download slots, including retries. Every
/// attempt has a cancellable deadline so stalled sockets cannot block the pool.
class BilibiliImageFileService extends FileService {
  final Dio _client;
  final Duration attemptTimeout;
  BilibiliImageFileService({
    Dio? client,
    this.attemptTimeout = const Duration(seconds: 6),
  }) : _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 4),
               receiveTimeout: const Duration(seconds: 5),
             ),
           ) {
    concurrentFetches = 4;
    if (client == null) {
      _client.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: createImageHttpClient,
      );
    }
  }

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final candidates = imageDownloadCandidates(url);
    Object? lastError;
    for (var i = 0; i < candidates.length; i++) {
      final uri = candidates[i];
      final cancel = CancelToken();
      final deadline = Timer(
        attemptTimeout,
        () => cancel.cancel('image deadline'),
      );
      try {
        final response = await _client.get<List<int>>(
          uri.toString(),
          options: Options(
            responseType: ResponseType.bytes,
            headers: headers,
            validateStatus: (_) => true,
          ),
          cancelToken: cancel,
          onReceiveProgress: (received, total) {
            if (received > 4 * 1024 * 1024) cancel.cancel('image size limit');
          },
        );
        final status = response.statusCode ?? 0;
        if (status == 200 || status == 304) return _ImageResponse(response);
        lastError = HttpException('Image HTTP $status');
        _imageLog.w('图片节点 ${uri.host} HTTP $status，尝试备用节点');
        if (status == 401 || status == 429) break;
      } on DioException catch (error) {
        lastError = error;
        final cause = error.error;
        _imageLog.w(
          '图片节点 ${uri.host} ${error.type.name}${cause is SocketException ? ' errno=${cause.osError?.errorCode}' : ''}，尝试备用节点',
        );
        if (cancel.cancelError?.message == 'image size limit') break;
      } finally {
        deadline.cancel();
      }
    }
    throw lastError ?? const HttpException('Image download failed');
  }
}

class _ImageResponse implements FileServiceResponse {
  final Response<List<int>> response;
  _ImageResponse(this.response);
  @override
  Stream<List<int>> get content => Stream.value(response.data ?? const []);
  @override
  int? get contentLength => response.data?.length;
  @override
  int get statusCode => response.statusCode!;
  @override
  String? get eTag => response.headers.value('etag');
  @override
  DateTime get validTill {
    final control = response.headers.value('cache-control') ?? '';
    final seconds = int.tryParse(
      RegExp(r'max-age=(\d+)').firstMatch(control)?.group(1) ?? '',
    );
    return DateTime.now().add(
      control.contains('no-cache')
          ? Duration.zero
          : Duration(seconds: seconds ?? 604800),
    );
  }

  @override
  String get fileExtension {
    final mime = response.headers.value('content-type')?.split(';').first;
    return switch (mime) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      _ => '.jpg',
    };
  }
}
