# 🛠️ 开发踩坑与避坑指南

> 本文档记录开发过程中遇到的问题和解决方案，持续更新。

---

## [2026-02-09] MinSDK 版本冲突（21 vs 24）

### 现象描述
云端构建报错：`uses-sdk:minSdkVersion 21 cannot be smaller than version 24 declared in library [:ffmpeg_kit_flutter_new]`

### 根本原因
`ffmpeg_kit_flutter_new`（及许多现代音视频库）依赖的底层 API 需要 Android 7.0 (API 24) 以上，而项目配置的是 21。

### 解决方案
将 MinSDK 提升至 **24**：
1. 修改 `android/app/build.gradle` (在 `build.yml` 中自动修改)
2. 修改 `pubspec.yaml` 中的 `flutter_launcher_icons` 配置

### 避坑建议
- 处理音视频功能时，默认 MinSDK 21 通常不够用，建议起步 24
- 遇到 `Manifest merger failed` 优先检查 SDK 版本

---

## [2026-02-09] FFmpeg 插件版本不存在

### 现象描述
云端构建报错：`ffmpeg_kit_flutter_new ^6.0.3 which doesn't match any versions`

### 根本原因
pub.dev 上 `ffmpeg_kit_flutter_new` 最新版本是 `4.1.0`，`6.0.3` 版本根本不存在。

### 解决方案
将 `pubspec.yaml` 中的版本从 `^6.0.3` 改为 `^4.1.0`。

### 避坑建议
- 添加依赖前先去 [pub.dev](https://pub.dev) 确认实际可用版本
- 不要凭记忆或猜测写版本号

---

## [2026-02-09] 技术选型：FFmpegKit 已退役

### 现象描述
原本计划使用 `ffmpeg_kit_flutter` 官方插件。

### 根本原因
FFmpegKit 官方团队已宣布退役，GitHub 仓库归档，不再维护。

### 解决方案
改用社区维护版 `ffmpeg_kit_flutter_new`，该插件持续更新并兼容最新 Flutter 版本。

### 避坑建议
- 使用第三方库前，先检查其维护状态
- 优先选择社区活跃的分支/替代品

---

## [2026-02-09] 无损剪切的关键帧限制

### 现象描述
使用 `-c copy` 剪切视频时，起始时间不精确，可能比设定的时间早 1-2 秒。

### 根本原因
视频编码原理：只能在关键帧（I-frame）处切割。如果你设定的时间点不是关键帧，FFmpeg 会自动回退到最近的关键帧。

### 解决方案
这是无损剪切的固有限制，**无法规避**。用户需理解并接受。

### 避坑建议
- 在 UI 上明确提示用户"切点可能存在 1-2 秒偏差"
- 如果需要精确到帧，必须使用重编码模式（会有画质损失）

---

## [2026-02-09] 无损合并要求格式一致

### 现象描述
合并两个视频时，FFmpeg 报错或输出异常。

### 根本原因
无损合并（concat demuxer）要求所有视频片段：
- 分辨率相同
- 编码器相同（如都是 H.264）
- 音频采样率相同

### 解决方案
1. 在 UI 提示用户"请确保视频格式一致"
2. 如格式不一致，需先转码统一格式后再合并

### 避坑建议
- 合并手机拍摄的视频通常没问题（格式一致）
- 合并不同来源的视频容易出问题

---

## [2026-02-09] FFmpeg 日志输出调试

### 现象描述
FFmpeg 命令执行失败，但不知道具体原因。

### 解决方案
在代码中添加日志输出：
```dart
final logs = await session.getAllLogsAsString();
print('FFmpeg 日志: $logs');
```

### 避坑建议
- 开发阶段保留详细日志
- 正式发布可以精简日志输出
