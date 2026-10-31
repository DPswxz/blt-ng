import 'package:blt/consts/settings.dart';
import 'package:blt/widgets/playback_mode_icon.dart';
import 'package:blt/consts/danmaku.dart';
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
  int _audio = 0;
  bool _danmakuEnabled = true;
  int _fontSize = defaultDanmakuFontSize;
  int _area = defaultDanmakuArea;
  int _transparency = defaultDanmakuTransparency;
  int _weight = 6;
  PlayerLoopMode _loopMode = PlayerLoopMode.none;
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
    _audio = await Settings.getInt(Settings.pathPreferredAudio) ?? 0;
    _loopMode =
        PlayerLoopMode.parse(
          await Settings.getString(Settings.pathLoopModeSwitch),
        ) ??
        PlayerLoopMode.none;
    _danmakuEnabled = await Settings.getBool(Settings.pathDanmuSwitch) ?? true;
    _fontSize =
        await Settings.getInt(Settings.pathDanmuFontSize) ??
        defaultDanmakuFontSize;
    _area = await Settings.getInt(Settings.pathDanmuArea) ?? defaultDanmakuArea;
    _transparency =
        (await Settings.getInt(Settings.pathDanmuTransparency) ??
                defaultDanmakuTransparency)
            .clamp(0, 90);
    _weight = await Settings.getInt(Settings.pathDanmuBlockWeightSwitch) ?? 6;
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final ui = context.ui;
    return Padding(
      padding: EdgeInsets.fromLTRB(8 * ui, 8 * ui, 8 * ui, 16 * ui),
      child: Text(
        title,
        style: TextStyle(fontSize: 28 * ui, fontWeight: FontWeight.w700),
      ),
    );
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
            _sectionTitle(context, '播放设置'),
            CustomSettingsPanel(
              children: [
                CustomSettingsDropdownTile<String>(
                  leading: const Icon(Icons.high_quality),
                  title: '进入视频默认画质',
                  subtitle:
                      '每个视频按默认画质进入，无对应画质或权限时选择较低档位。4K、1080P 高码率需要片源支持及大会员权限。',
                  value:
                      defaultQualityLabels[_quality] ??
                      defaultQualityLabels[80]!,
                  items: defaultQualityLabels.values.toList(),
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
                CustomSettingsDropdownTile<String>(
                  leading: const Icon(Icons.audiotrack),
                  title: '音轨设置',
                  subtitle: '优先使用所选音轨，片源不支持时使用最高码率音轨。',
                  value:
                      preferredAudioLabels[_audio] ?? preferredAudioLabels[0]!,
                  items: preferredAudioLabels.values.toList(),
                  onChanged: (value) => setState(() {
                    _audio = preferredAudioLabels.entries
                        .firstWhere((e) => e.value == value)
                        .key;
                    Settings.setInt(Settings.pathPreferredAudio, _audio);
                  }),
                ),
                CustomSettingsDropdownTile<String>(
                  leading: Icon(playbackModeIcon(_loopMode)),
                  title: '播放完后',
                  value: _loopMode.description,
                  items: PlayerLoopMode.values
                      .map((mode) => mode.description)
                      .toList(),
                  onChanged: (value) => setState(() {
                    _loopMode = PlayerLoopMode.values.firstWhere(
                      (mode) => mode.description == value,
                    );
                    Settings.setString(
                      Settings.pathLoopModeSwitch,
                      _loopMode.value,
                    );
                  }),
                ),
              ],
            ),
            SizedBox(height: 24 * ui),
            _sectionTitle(context, '弹幕设置'),
            CustomSettingsPanel(
              children: [
                CustomSettingsSwitchTile(
                  leading: const Icon(Icons.subtitles_outlined),
                  title: '开启弹幕',
                  value: _danmakuEnabled,
                  onChanged: (value) => setState(() {
                    _danmakuEnabled = value;
                    Settings.setBool(Settings.pathDanmuSwitch, value);
                  }),
                ),
                CustomSettingsDropdownTile<int>(
                  leading: const Icon(Icons.format_size),
                  title: '弹幕字体大小',
                  value: _fontSize,
                  items: danmakuFontSizes,
                  onChanged: (value) => setState(() {
                    _fontSize = value;
                    Settings.setInt(Settings.pathDanmuFontSize, value);
                  }),
                ),
                CustomSettingsDropdownTile<String>(
                  leading: const Icon(Icons.vertical_align_top),
                  title: '显示区域',
                  value:
                      danmakuAreaLabels[_area] ??
                      danmakuAreaLabels[defaultDanmakuArea]!,
                  items: danmakuAreaLabels.values.toList(),
                  onChanged: (value) => setState(() {
                    _area = danmakuAreaLabels.entries
                        .firstWhere((e) => e.value == value)
                        .key;
                    Settings.setInt(Settings.pathDanmuArea, _area);
                  }),
                ),
                CustomSettingsDropdownTile<String>(
                  leading: const Icon(Icons.opacity),
                  title: '透明度',
                  value: danmakuTransparencyLabel(_transparency),
                  items: danmakuTransparencies
                      .map(danmakuTransparencyLabel)
                      .toList(),
                  onChanged: (value) => setState(() {
                    _transparency = danmakuTransparencies.firstWhere(
                      (v) => danmakuTransparencyLabel(v) == value,
                    );
                    Settings.setInt(
                      Settings.pathDanmuTransparency,
                      _transparency,
                    );
                  }),
                ),
                CustomSettingsDropdownTile<int>(
                  leading: const Icon(Icons.filter_alt_outlined),
                  title: '弹幕屏蔽权重',
                  subtitle: '权重越大，显示的弹幕越少。',
                  value: _weight,
                  items: List.generate(11, (i) => i),
                  onChanged: (value) => setState(() {
                    _weight = value;
                    Settings.setInt(Settings.pathDanmuBlockWeightSwitch, value);
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
