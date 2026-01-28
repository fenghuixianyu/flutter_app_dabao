/// 时间解析工具
/// 
/// 将用户输入的各种时间格式转换为秒
class TimeParser {
  /// 解析时间字符串为秒
  /// 
  /// 支持格式：
  /// - "1.5" -> 90秒 (默认单位：分钟)
  /// - "90" -> 90秒 (纯数字，默认分钟)
  /// - "1:30" -> 90秒 (分:秒)
  /// - "00:01:30" -> 90秒 (时:分:秒)
  static double? parseToSeconds(String input) {
    input = input.trim();
    if (input.isEmpty) return null;

    // 如果包含冒号，按 HH:MM:SS 或 MM:SS 格式解析
    if (input.contains(':')) {
      final parts = input.split(':');
      try {
        if (parts.length == 2) {
          // MM:SS 格式
          final minutes = double.parse(parts[0]);
          final seconds = double.parse(parts[1]);
          return minutes * 60 + seconds;
        } else if (parts.length == 3) {
          // HH:MM:SS 格式
          final hours = double.parse(parts[0]);
          final minutes = double.parse(parts[1]);
          final seconds = double.parse(parts[2]);
          return hours * 3600 + minutes * 60 + seconds;
        }
      } catch (_) {
        return null;
      }
    }

    // 纯数字，默认作为分钟处理
    try {
      final minutes = double.parse(input);
      return minutes * 60;
    } catch (_) {
      return null;
    }
  }

  /// 解析时间区间
  /// 
  /// 如 "1-2" 解析为 {start: 60, end: 120}
  static Map<String, double>? parseInterval(String input) {
    input = input.trim();
    if (!input.contains('-')) return null;

    final parts = input.split('-');
    if (parts.length != 2) return null;

    final start = parseToSeconds(parts[0]);
    final end = parseToSeconds(parts[1]);

    if (start == null || end == null) return null;
    if (start >= end) return null;

    return {'start': start, 'end': end};
  }

  /// 格式化秒数为可读字符串
  /// 
  /// 如 90 秒 -> "1:30"
  static String formatSeconds(double seconds) {
    final totalSeconds = seconds.round();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
  }

  /// 格式化秒数为 FFmpeg 格式
  /// 
  /// 如 90.5 秒 -> "00:01:30.500"
  static String formatForFFmpeg(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = seconds % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toStringAsFixed(3).padLeft(6, '0')}';
  }
}
