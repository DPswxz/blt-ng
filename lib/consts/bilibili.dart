const coverSizeRatio = 16 / 10;

// const vq240P = VideoQuality(6, '240P 极速');
const vq360P = VideoQuality(16, '360P 流畅');
const vq480P = VideoQuality(32, '480P 清晰');
const vq720P = VideoQuality(64, '720P 高清');
const vq720P60 = VideoQuality(74, '720P60 高帧率', needLogin: true);
const vq1080P = VideoQuality(80, '1080P 高清', needLogin: true);
const vqRepair = VideoQuality(100, '智能修复', needLogin: true, needVIP: true);
const vq1080PPlus = VideoQuality(
  112,
  '1080P+ 高码率',
  needLogin: true,
  needVIP: true,
);
const vq4K = VideoQuality(120, '4K 超清', needLogin: true, needVIP: true);
// const vqHDR = VideoQuality(125, 'HDR 真彩色', needLogin: true, needVIP: true);
// const vqDolbyVision = VideoQuality(126, '杜比视界', needLogin: true, needVIP: true);
// const vq8K = VideoQuality(127, '8K 超高清', needLogin: true, needVIP: true);
const vqHDRVivid = VideoQuality(
  129,
  'HDR Vivid',
  needLogin: true,
  needVIP: true,
);

class VideoQuality {
  final int index;
  final String name;
  final bool needLogin;
  final bool needVIP;
  const VideoQuality(
    this.index,
    this.name, {
    this.needLogin = false,
    this.needVIP = false,
  });
  static const List<VideoQuality> values = [
    // vq240P,
    vq360P,
    vq480P,
    vq720P,
    vq720P60,
    vq1080P,
    vqRepair,
    vq1080PPlus,
    vq4K,
    // vqHDR,
    // vqDolbyVision,
    // vq8K,
    vqHDRVivid,
  ];
}
