import 'package:blt/apis/bilibili/media.dart';
import 'package:blt/utils/playback_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Quality> qualities(List<int> ids) => [
    for (final id in ids) Quality(id: id, description: '$id'),
  ];
  test('默认高码率按可用权限回退，普通1080P不自动升档', () {
    final all = qualities([120, 112, 80, 64, 32]);
    expect(defaultQualityOrder(all, 120).map((q) => q.id), [120, 80, 64, 32]);
    expect(defaultQualityOrder(all, 112).map((q) => q.id), [112, 80, 64, 32]);
    expect(defaultQualityOrder(all, 80).map((q) => q.id), [80, 64, 32]);
    final restricted = qualities([80, 64]);
    expect(defaultQualityOrder(restricted, 112).first.id, 80);
    expect(defaultQualityOrder(restricted, 120).first.id, 80);
  });
}
