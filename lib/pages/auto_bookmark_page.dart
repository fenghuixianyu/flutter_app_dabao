import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/python_service.dart';

class AutoBookmarkPage extends StatefulWidget {
  const AutoBookmarkPage({super.key});

  @override
  State<AutoBookmarkPage> createState() => _AutoBookmarkPageState();
}

class _AutoBookmarkPageState extends State<AutoBookmarkPage> {
  String? _inputFolder;
  String? _outputFolder;
  bool _isRunning = false;
  String _logs = "";
  
  // Basic Config State
  final TextEditingController _level1Regex = TextEditingController(text: r"^\s*第[一二三四五六七八九十百]+章\s*\S+");
  final TextEditingController _level1Size = TextEditingController(text: "15");
  
  Future<void> _pickInput() async {
    String? path = await FilePicker.platform.getDirectoryPath();
    if (path != null) setState(() => _inputFolder = path);
  }

  Future<void> _pickOutput() async {
     String? path = await FilePicker.platform.getDirectoryPath();
    if (path != null) setState(() => _outputFolder = path);
  }

  Future<void> _runTask() async {
    if (_inputFolder == null || _outputFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select folders")));
      return;
    }
    
    setState(() {
      _isRunning = true;
      _logs = "Starting task...\n";
    });

    // Build Config JSON
    // Only implemented level 1 basic for demo, full config would be a larger form
    final config = {
      "level1": {
        "regex": _level1Regex.text,
        "font_size": int.tryParse(_level1Size.text) ?? 15
      },
      "level2": {
         "regex": r"^\s*[一二三四五六七八九十百]+、\s*\S+",
         "font_size": 12
      },
      "exclusion": {
          "min_y_coord": 50,
          "max_y_coord": 800,
          "max_line_length": 40
      }
    };

    final result = await PythonService.runScript('auto_shuqian', {
      'input_folder': _inputFolder,
      'output_folder': _outputFolder,
      'config': config
    });

    setState(() {
      _isRunning = false;
      String currentLogs = result['logs'] ?? "No logs";
      if (result['success'] == true) {
         currentLogs += "\n DONE!";
      } else {
         currentLogs += "\n FAILED: " + (result['message'] ?? "Unknown error");
      }
      _logs = currentLogs;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Auto Bookmarks")),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                 _buildFolderPicker("Input Folder", _inputFolder, _pickInput),
                 const SizedBox(height: 10),
                 _buildFolderPicker("Output Folder", _outputFolder, _pickOutput), 
                 const SizedBox(height: 20),
                 const Text("Rule Configuration", style: TextStyle(fontWeight: FontWeight.bold)),
                 const SizedBox(height: 10),
                 TextField(
                   controller: _level1Regex,
                   decoration: const InputDecoration(labelText: "Level 1 Regex", border: OutlineInputBorder()),
                 ),
                 const SizedBox(height: 10),
                 TextField(
                   controller: _level1Size,
                   keyboardType: TextInputType.number,
                   decoration: const InputDecoration(labelText: "Level 1 Min Font Size", border: OutlineInputBorder()),
                 ),
              ],
            ),
          ),
          Container(
             color: Colors.black87,
             height: 150,
             width: double.infinity,
             padding: const EdgeInsets.all(8),
             child: SingleChildScrollView(
               child: Text(_logs, style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')),
             ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
               width: double.infinity,
               height: 50,
               child: ElevatedButton(
                 onPressed: _isRunning ? null : _runTask,
                 style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                 child: _isRunning ? const CircularProgressIndicator(color: Colors.white) : const Text("RUN AUTO BOOKMARK", style: TextStyle(color: Colors.white, fontSize: 16)),
               ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFolderPicker(String label, String? path, VoidCallback onPick) {
    return InkWell(
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.folder_open),
        ),
        child: Text(path ?? "Select Folder...", style: TextStyle(color: path == null ? Colors.grey : Colors.black)),
      ),
    );
  }
}
