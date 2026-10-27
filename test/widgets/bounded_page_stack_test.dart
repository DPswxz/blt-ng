import 'package:blt/widgets/bounded_page_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

class Probe extends StatefulWidget {
  final int id;
  final Set<int> alive;
  final Map<int, int> created;
  const Probe(this.id, this.alive, this.created, {super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  @override
  void initState() {
    super.initState();
    widget.alive.add(widget.id);
    widget.created.update(widget.id, (v) => v + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    widget.alive.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Text('page${widget.id}');
}

void main() {
  setupPageTestEnv();
  testWidgets('反复切换只保留两个页面，离开搜索即销毁，内存压力回收后台页', (t) async {
    final index = ValueNotifier(0);
    final alive = <int>{};
    final created = <int, int>{};
    await pumpPage(
      t,
      ValueListenableBuilder<int>(
        valueListenable: index,
        builder: (c, i, _) => BoundedPageStack(
          index: i,
          discardWhenInactive: const {1},
          children: [
            for (var n = 0; n < 6; n++)
              Probe(n, alive, created, key: ValueKey(n)),
          ],
        ),
      ),
    );
    for (var round = 0; round < 6; round++) {
      for (var i = 0; i < 6; i++) {
        index.value = i;
        await t.pump();
        expect(alive.length, lessThanOrEqualTo(2));
        expect(alive, contains(i));
        if (i != 1) expect(alive, isNot(contains(1)));
      }
    }
    expect(created[1], 6);
    t.binding.handleMemoryPressure();
    await t.pump();
    expect(alive, {5});
    await t.pumpWidget(const SizedBox());
    expect(alive, isEmpty);
    index.dispose();
  });
}
