const defaultDanmakuFontSize = 30;
const defaultDanmakuTransparency = 40;
const defaultDanmakuArea = 10;
const danmakuFontSizes = [25, 28, 30, 36, 40, 48, 56];
const danmakuTransparencies = [0, 20, 40, 60, 80, 90];
const danmakuAreaLabels = {
  5: '顶部 5%',
  10: '顶部 10%',
  25: '顶部 25%',
  50: '顶部 50%',
};
String danmakuTransparencyLabel(int value) =>
    value == 0 ? '0%（不透明）' : '$value%';

const defaultDanmakuSpeed = 1;
const danmakuSpeedLabels = {0: '慢', 1: '中', 2: '高'};
const danmakuSpeedDurations = {0: 14, 1: 10, 2: 6};
