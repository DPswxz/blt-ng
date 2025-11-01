// 未登陆
const noLoginError = BilibiliError(-101, '未登录');

// bilibili错误
class BilibiliError implements Exception {
  final int code;
  final String message;
  const BilibiliError(this.code, this.message);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BilibiliError) return false;
    return code == other.code;
  }

  @override
  int get hashCode => code.hashCode;
}
