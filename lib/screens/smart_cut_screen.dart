import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/ffmpeg_service.dart';
import '../utils/time_parser.dart';

/// 智能剪切页面
class SmartCutScreen extends StatefulWidget {
  const SmartCutScreen({super.key});

  @override
  State<SmartCutScreen> createState() => _SmartCutScreenState();
}

class _SmartCutScreenState extends State<SmartCutScreen> {
  final FFmpegService _ffmpeg = FFmpegService();
  
  String? _selectedPath;
  String? _videoName;
  String? _videoSize;
  VideoMeta? _videoMeta;
  
  final List<Map<String, double>> _segments = [];
  final TextEditingController _timeCtrl = TextEditingController();
  
  bool _mergeMode = false;
  bool _overwriteMode = false;
  bool _isProcessing = false;
  String _status = '';
  double _progress = 0;

  @override
  void dispose() {
    _timeCtrl.dispose();
    _ffmpeg.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedPath = file.path;
          _videoName = file.name;
          _videoSize = _formatSize(file.size);
          _segments.clear();
          _status = '正在分析...';
        });

        if (file.path != null) {
          final meta = await _ffmpeg.analyzeVideo(file.path!);
          if (meta != null && mounted) {
            setState(() {
              _videoMeta = meta;
              _status = '时长: ${TimeParser.formatSeconds(meta.duration)}';
            });
          }
        }
      }
    } catch (e) {
      _showError('选择失败: $e');
    }
  }

  void _addSegment() {
    final input = _timeCtrl.text.trim();
    if (input.isEmpty) { _showError('请输入时间区间'); return; }
    
    final interval = TimeParser.parseInterval(input);
    if (interval == null) { _showError('格式错误，如 "1-2" 表示1到2分钟'); return; }
    
    setState(() { _segments.add(interval); _timeCtrl.clear(); });
  }

  Future<void> _execute() async {
    if (_selectedPath == null) { _showError('请先选择视频'); return; }
    if (_segments.isEmpty) { _showError('请添加时间片段'); return; }

    setState(() { _isProcessing = true; _progress = 0; _status = '处理中...'; });

    try {
      final dir = await getTemporaryDirectory();
      final base = _videoName?.split('.').first ?? 'out';
      final ext = _selectedPath!.split('.').last;
      List<String> outputs = [];

      for (int i = 0; i < _segments.length; i++) {
        final seg = _segments[i];
        final suffix = _segments.length > 1 ? '_cut_${i+1}' : '_cut';
        final outPath = '${dir.path}/$base$suffix.$ext';
        
        setState(() { _progress = i / _segments.length * 0.8; _status = '剪切 ${i+1}/${_segments.length}...'; });
        
        final ok = await _ffmpeg.cutVideo(
          inputPath: _selectedPath!,
          outputPath: outPath,
          startSeconds: seg['start']!,
          endSeconds: seg['end']!,
        );
        if (!ok) throw Exception('剪切失败');
        outputs.add(outPath);
      }

      String finalOut;
      if (_mergeMode && outputs.length > 1) {
        setState(() { _status = '合并中...'; _progress = 0.9; });
        finalOut = '${dir.path}/${base}_merged.$ext';
        final ok = await _ffmpeg.stitchSameGroup(inputPaths: outputs, outputPath: finalOut);
        if (!ok) throw Exception('合并失败');
        for (final f in outputs) { try { File(f).deleteSync(); } catch(_) {} }
      } else {
        finalOut = outputs.first;
      }

      if (_overwriteMode) {
        final newFile = File(finalOut);
        if (newFile.lengthSync() > 100) {
          File(_selectedPath!).deleteSync();
          newFile.renameSync(_selectedPath!);
          finalOut = _selectedPath!;
        }
      }

      setState(() { _progress = 1; _status = '✅ 完成: ${finalOut.split('/').last}'; _isProcessing = false; });
      _showSuccess('剪切完成');
    } catch (e) {
      setState(() { _isProcessing = false; _status = '❌ 失败: $e'; });
      _showError('$e');
    }
  }

  String _formatSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024*1024) return '${(b/1024).toStringAsFixed(1)} KB';
    if (b < 1024*1024*1024) return '${(b/(1024*1024)).toStringAsFixed(1)} MB';
    return '${(b/(1024*1024*1024)).toStringAsFixed(2)} GB';
  }

  void _showError(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));
  void _showSuccess(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.green));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('智能剪切')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 提示
          Card(color: cs.surfaceContainerHighest, child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber),
              SizedBox(width: 8),
              Expanded(child: Text('输入 "1-2" 表示剪切1到2分钟\n支持多段剪切后合并', style: TextStyle(fontSize: 13))),
            ]),
          )),
          const SizedBox(height: 16),
          
          // 选择视频
          Card(child: InkWell(
            onTap: _isProcessing ? null : _pickVideo,
            borderRadius: BorderRadius.circular(12),
            child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
              Icon(_selectedPath != null ? Icons.video_file : Icons.add_circle_outline, size: 48, color: cs.primary),
              const SizedBox(height: 12),
              Text(_videoName ?? '点击选择视频', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (_videoSize != null) Text(_videoSize!, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ])),
          )),
          const SizedBox(height: 16),
          
          // 时间输入
          Row(children: [
            Expanded(child: TextField(
              controller: _timeCtrl,
              enabled: !_isProcessing,
              decoration: InputDecoration(
                labelText: '时间区间', hintText: '如: 1-2',
                prefixIcon: const Icon(Icons.timer),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _addSegment(),
            )),
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: _isProcessing ? null : _addSegment, icon: const Icon(Icons.add), label: const Text('添加')),
          ]),
          const SizedBox(height: 16),
          
          // 片段列表
          if (_segments.isNotEmpty) Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Text('已添加片段', style: TextStyle(fontWeight: FontWeight.w600))),
            ListView.separated(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              itemCount: _segments.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = _segments[i];
                return ListTile(
                  leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: Text('${i+1}')),
                  title: Text('${TimeParser.formatSeconds(s['start']!)} - ${TimeParser.formatSeconds(s['end']!)}'),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: _isProcessing ? null : () => setState(() => _segments.removeAt(i))),
                );
              },
            ),
          ])),
          const SizedBox(height: 16),
          
          // 开关
          Card(child: Column(children: [
            SwitchListTile(title: const Text('合并模式'), subtitle: const Text('多片段合并为一个文件'), value: _mergeMode, onChanged: _isProcessing ? null : (v) => setState(() => _mergeMode = v)),
            const Divider(height: 1),
            SwitchListTile(title: const Text('覆盖原文件'), subtitle: const Text('处理完成后替换原视频'), value: _overwriteMode, onChanged: _isProcessing ? null : (v) => setState(() => _overwriteMode = v)),
          ])),
          const SizedBox(height: 24),
          
          // 执行
          FilledButton.icon(
            onPressed: _isProcessing ? null : _execute,
            icon: _isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.content_cut),
            label: Text(_isProcessing ? '处理中...' : '开始剪切'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
          const SizedBox(height: 16),
          
          // 状态
          if (_status.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_isProcessing) LinearProgressIndicator(value: _progress),
            if (_isProcessing) const SizedBox(height: 12),
            Text(_status),
          ]))),
        ]),
      ),
    );
  }
}
