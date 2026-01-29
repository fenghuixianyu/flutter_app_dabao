import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/ffmpeg_service.dart';

/// 无损拼接页面
class AutoStitchScreen extends StatefulWidget {
  const AutoStitchScreen({super.key});

  @override
  State<AutoStitchScreen> createState() => _AutoStitchScreenState();
}

class _AutoStitchScreenState extends State<AutoStitchScreen> {
  List<VideoMeta> _videos = [];
  bool _deleteSource = false;
  bool _isProcessing = false;
  String _status = '';

  // 分组颜色
  static const List<Color> _groupColors = [
    Colors.green, Colors.blue, Colors.orange, Colors.purple, Colors.teal,
    Colors.pink, Colors.indigo, Colors.amber, Colors.cyan, Colors.lime,
  ];

  Future<void> _pickVideos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() { _status = '正在分析视频...'; });
        
        List<VideoMeta> analyzed = [];
        for (final file in result.files) {
          if (file.path == null) continue;
          final meta = await FFmpegService.analyzeVideo(file.path!);
          if (meta != null) analyzed.add(meta);
        }

        // 分组
        _assignGroups(analyzed);
        
        setState(() {
          _videos = analyzed;
          _status = '已选择 ${analyzed.length} 个视频';
        });
      }
    } catch (e) {
      // 忽略 "File picker is already active" 错误
      if (e.toString().contains('already_active')) return;
      _showError('选择失败: $e');
    }
  }

  void _assignGroups(List<VideoMeta> videos) {
    Map<String, int> groupMap = {};
    int groupIndex = 0;
    
    for (final v in videos) {
      final fp = v.fingerprint;
      if (!groupMap.containsKey(fp)) {
        groupMap[fp] = groupIndex++;
      }
      v.groupColorIndex = groupMap[fp];
      v.groupLabel = String.fromCharCode(65 + groupMap[fp]!); // A, B, C...
    }
  }

  bool get _isSameGroup {
    if (_videos.length < 2) return true;
    final first = _videos.first.fingerprint;
    return _videos.every((v) => v.fingerprint == first);
  }

  Future<void> _execute() async {
    if (_videos.length < 2) { _showError('请选择至少2个视频'); return; }

    setState(() { _isProcessing = true; _status = '拼接中...'; });

    try {
      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/stitch_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      // 目前只支持同组无损拼接
      if (!_isSameGroup) {
        setState(() { _status = '⚠️ 异组视频暂不支持，请选择相同规格的视频'; });
        _showError('异组视频暂不支持，请选择相同规格的视频');
        setState(() { _isProcessing = false; });
        return;
      }
      
      setState(() { _status = '同组视频，无损拼接中...'; });
      final success = await FFmpegService.stitchVideos(
        inputs: _videos.map((v) => v.path).toList(),
        output: outPath,
      );

      if (!success) throw Exception('拼接失败');

      if (_deleteSource) {
        for (final v in _videos) {
          try { File(v.path).deleteSync(); } catch (_) {}
        }
      }

      setState(() {
        _isProcessing = false;
        _status = '✅ 完成: ${outPath.split('/').last}';
        _videos.clear();
      });
      _showSuccess('拼接完成');
    } catch (e) {
      setState(() { _isProcessing = false; _status = '❌ 失败: $e'; });
      _showError('$e');
    }
  }

  void _removeVideo(int index) {
    setState(() {
      _videos.removeAt(index);
      _assignGroups(_videos);
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _videos.removeAt(oldIndex);
      _videos.insert(newIndex, item);
    });
  }

  void _showError(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));
  void _showSuccess(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.green));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('无损拼接')),
      body: Column(children: [
        // 提示
        Card(
          margin: const EdgeInsets.all(16),
          color: cs.surfaceVariant,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.lightbulb_outline, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '相同 [组] 的视频可无损秒拼\n请选择相同规格的视频',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              )),
            ]),
          ),
        ),
        
        // 视频列表
        Expanded(
          child: _videos.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.video_library_outlined, size: 80, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text('点击下方按钮选择视频', style: TextStyle(color: Colors.grey[500])),
                ]))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _videos.length,
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                    final v = _videos[index];
                    final color = _groupColors[v.groupColorIndex! % _groupColors.length];
                    return Card(
                      key: ValueKey(v.path),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.2),
                          child: Text(v.groupLabel!, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(v.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${v.resolution} | ${v.fps.round()}fps', style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _isProcessing ? null : () => _removeVideo(index),
                        ),
                      ),
                    );
                  },
                ),
        ),
        
        // 底部操作区
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceVariant,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            // 策略提示
            if (_videos.length >= 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(_isSameGroup ? Icons.flash_on : Icons.warning_amber, 
                      color: _isSameGroup ? Colors.green : Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _isSameGroup ? '同组视频 - 无损极速拼接' : '⚠️ 异组视频 - 请选择相同规格',
                    style: TextStyle(color: _isSameGroup ? Colors.green : Colors.orange),
                  ),
                ]),
              ),
            
            // 删除源文件开关
            SwitchListTile(
              dense: true,
              title: const Text('拼接后删除源文件'),
              value: _deleteSource,
              onChanged: _isProcessing ? null : (v) => setState(() => _deleteSource = v),
            ),
            
            // 状态
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_status, style: const TextStyle(fontSize: 13)),
              ),
            
            // 按钮
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _pickVideos,
                  icon: const Icon(Icons.add),
                  label: Text(_videos.isEmpty ? '选择视频' : '添加更多'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isProcessing || _videos.length < 2 || !_isSameGroup ? null : _execute,
                  icon: _isProcessing 
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.merge),
                  label: Text(_isProcessing ? '处理中...' : '开始拼接'),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
