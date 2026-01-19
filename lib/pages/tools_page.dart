import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/python_service.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  String? _folder;
  String? _logs = "";
  bool _isRunning = false;

  Future<void> _pickFolder() async {
    String? path = await FilePicker.platform.getDirectoryPath();
    if (path != null) setState(() => _folder = path);
  }

  Future<void> _runScript(String scriptName, String label) async {
    if (_folder == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a folder first")));
      return;
    }
    
    setState(() {
      _isRunning = true;
      _logs = "Running $label...\n";
    });

    // Capture local variable for null promotion
    final String targetFolder = _folder!;
    final args = {
        'source_folder': targetFolder, // for add bookmarks
        'input_folder': targetFolder,  // for tools
        'output_folder': targetFolder + "/output",
        'offset': 0
    };

    final result = await PythonService.runScript(scriptName, args);

    setState(() {
      _isRunning = false;
      _logs = result['logs'] ?? "";
      if (result['success'] == true) _logs = "$_logs\nSUCCESS";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tools")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: InkWell(
              onTap: _pickFolder,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: "Target Folder", 
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.folder),
                ),
                child: Text(_folder ?? "Select Target Folder containing PDFs..."),
              ),
            ),
          ),
          
          Expanded(
            child: ListView(
               padding: const EdgeInsets.symmetric(horizontal: 16),
               children: [
                 ElevatedButton.icon(
                   icon: const Icon(Icons.analytics),
                   label: const Text("Run Inspector (Analyze PDF)"),
                   onPressed: _isRunning ? null : () => _runScript('inspector', 'Inspector'),
                 ),
                 const SizedBox(height: 10),
                 ElevatedButton.icon(
                   icon: const Icon(Icons.file_upload),
                   label: const Text("Extract Bookmarks to TXT"),
                   onPressed: _isRunning ? null : () => _runScript('extract', 'Extract'),
                 ),
                 const SizedBox(height: 10),
                 ElevatedButton.icon(
                   icon: const Icon(Icons.save),
                   label: const Text("Add Bookmarks from TXT"),
                   onPressed: _isRunning ? null : () => _runScript('add_bookmarks', 'Add Bookmarks'),
                 ),
               ],
            ),
          ),
          
          Container(
             color: Colors.black87,
             height: 200,
             width: double.infinity,
             padding: const EdgeInsets.all(8),
             child: SingleChildScrollView(
               child: Text(_logs ?? "", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')),
             ),
          )
        ],
      )
    );
  }
}
