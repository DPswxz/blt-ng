import 'dart:io';
import 'dart:typed_data';
import 'package:blt/utils/image_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  test('图片连接通过IPv4建立，保留原始Host及连接池预算', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final request = server.first;
    final client = createImageHttpClient();
    expect(client.maxConnectionsPerHost, 4);
    final pending = client
        .getUrl(Uri.parse('http://localhost:${server.port}/image'))
        .then((r) => r.close());
    final incoming = await request;
    expect(
      incoming.connectionInfo!.remoteAddress.type,
      InternetAddressType.IPv4,
    );
    expect(incoming.headers.value('host'), startsWith('localhost:'));
    incoming.response.add([1, 2, 3]);
    await incoming.response.close();
    final response = await pending;
    expect(await response.expand((b) => b).toList(), [1, 2, 3]);
    client.close(force: true);
    await server.close(force: true);
  });
  test('公共图片使用HTTPS及同路径备用节点，保留签名及外部URL', () {
    expect(
      imageDownloadCandidates(
        'http://i0.hdslb.com/bfs/a.jpg@448w.webp',
      ).map((u) => u.host),
      ['i0.hdslb.com', 'i1.hdslb.com', 'i2.hdslb.com'],
    );
    expect(
      imageDownloadCandidates('//i1.hdslb.com/a.jpg').first.scheme,
      'https',
    );
    expect(
      imageDownloadCandidates('https://i0.hdslb.com/a.jpg?token=test').length,
      1,
    );
    expect(
      imageDownloadCandidates('https://example.org/a.jpg').single.host,
      'example.org',
    );
  });
  test('主节点连接失败后用备用节点，仍沿用缓存响应与下载并发限制', () async {
    final dio = Dio();
    final adapter = _FailoverAdapter();
    dio.httpClientAdapter = adapter;
    final transport = BilibiliImageFileService(client: dio);
    final result = await transport.get('https://i0.hdslb.com/a.jpg');
    expect(transport.concurrentFetches, 4);
    expect(result.statusCode, 200);
    expect(result.fileExtension, '.webp');
    expect(adapter.hosts, ['i0.hdslb.com', 'i1.hdslb.com']);
    expect(await result.content.expand((b) => b).toList(), isNotEmpty);
    expect(
      result.validTill.isAfter(DateTime.now().add(const Duration(minutes: 59))),
      isTrue,
    );
    dio.close(force: true);
  });
  test('失败不会无限循环，所有节点失败即返回错误', () async {
    final dio = Dio();
    final mock = DioAdapter(dio: dio);
    for (final host in ['i0', 'i1', 'i2']) {
      mock.onGet('https://$host.hdslb.com/a.jpg', (s) => s.reply(503, []));
    }
    await expectLater(
      BilibiliImageFileService(client: dio).get('https://i0.hdslb.com/a.jpg'),
      throwsA(isA<HttpException>()),
    );
    dio.close(force: true);
  });
}

class _FailoverAdapter implements HttpClientAdapter {
  final hosts = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    hosts.add(options.uri.host);
    if (hosts.length == 1) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const SocketException('test'),
      );
    }
    return ResponseBody.fromBytes(
      [1, 2, 3],
      200,
      headers: {
        'content-type': ['image/webp'],
        'cache-control': ['max-age=3600'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
