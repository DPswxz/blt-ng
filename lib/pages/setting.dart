import 'package:blt/storages/settings.dart';
import 'package:blt/utils/playback_policy.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/cache_future_builder.dart';
import 'package:blt/widgets/custom_setting_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class SettingPage extends StatefulWidget {
  final ValueListenable<int>? refreshListener;
  const SettingPage({super.key, this.refreshListener});
  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  int _quality = 80, _codec = 0;
  String _decoder = 'auto';
  @override
  void initState() {
    super.initState();
    widget.refreshListener?.addListener(_refresh);
  }

  void _refresh() {
    _loadSettings().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.refreshListener?.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _quality = await Settings.getInt(Settings.pathDefaultQuality) ?? 80;
    _codec = await Settings.getInt(Settings.pathPreferredCodec) ?? 0;
    _decoder = await Settings.getString(Settings.pathDecoderMode) ?? 'auto';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: CacheFutureBuilder(
      future: _loadSettings,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox();
        }
        final ui = context.ui;
        return ListView(
          padding: EdgeInsets.all(24 * ui),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8 * ui, 8 * ui, 8 * ui, 24 * ui),
              child: Text(
                '偏好设置',
                style: TextStyle(
                  fontSize: 32 * ui,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            CustomSettingsPanel(
              children: [
                CustomSettingsDropdownTile<String>(
                  leading: const Icon(Icons.high_quality),
                  title: '进入视频默认画质',
                  subtitle: '每个视频按默认画质进入，无对应画质或权限时选择较低档位。4K需要片源和账号支持。',
                  value:
                      defaultQualityLabels[_quality] ??
                      defaultQualityLabels[80]!,
                  items: defaultQualityLabels.values.toList(),
                  autofocus: true,
                  onChanged: (v) => setState(() {
                    _quality = defaultQualityLabels.entries
                        .firstWhere((e) => e.value == v)
                        .key;
                    Settings.setInt(Settings.pathDefaultQuality, _quality);
                  }),
                ),
                CustomSettingsDropdownTile<String>(
                  leading: const Icon(Icons.memory),
                  title: '解码方式',
                  value: decoderLabels[_decoder] ?? decoderLabels['auto']!,
                  items: decoderLabels.values.toList(),
                  onChanged: (v) => setState(() {
                    _decoder = decoderLabels.entries
                        .firstWhere((e) => e.value == v)
                        .key;
                    Settings.setString(Settings.pathDecoderMode, _decoder);
                  }),
                ),
                CustomSettingsDropdownTile<String>(
                  leading: const Icon(Icons.tune),
                  title: '视频编码偏好',
                  value:
                      preferredCodecLabels[_codec] ?? preferredCodecLabels[0]!,
                  items: preferredCodecLabels.values.toList(),
                  onChanged: (v) => setState(() {
                    _codec = preferredCodecLabels.entries
                        .firstWhere((e) => e.value == v)
                        .key;
                    Settings.setInt(Settings.pathPreferredCodec, _codec);
                  }),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
