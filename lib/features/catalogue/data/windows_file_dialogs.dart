import 'dart:io';

class WindowsFileDialogs {
  const WindowsFileDialogs();

  Future<String?> pickExcelFile() async {
    final output = await _runDialog('''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Title = 'Select Excel file'
\$dialog.Filter = 'Excel Workbook (*.xlsx)|*.xlsx|All Files (*.*)|*.*'
\$dialog.Multiselect = \$false
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dialog.FileName
}
''');
    return output;
  }

  Future<String?> pickLegacyCatalogueFile() async {
    final output = await _runDialog('''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Title = 'Select old Crimson catalogue data'
\$dialog.Filter = 'Catalogue Data (*.db;*.sqlite;*.sqlite3;*.json;*.xlsx)|*.db;*.sqlite;*.sqlite3;*.json;*.xlsx|All Files (*.*)|*.*'
\$dialog.Multiselect = \$false
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dialog.FileName
}
''');
    return output;
  }

  Future<String?> pickCatalogueBackupFile() async {
    final output = await _runDialog('''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Title = 'Select Crimson catalogue backup'
\$dialog.Filter = 'Crimson Backup (*.json)|*.json|All Files (*.*)|*.*'
\$dialog.Multiselect = \$false
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dialog.FileName
}
''');
    return output;
  }

  Future<String?> pickCatalogueBackupSavePath({
    String suggestedName = 'Crimson-Catalogue-Backup.json',
  }) async {
    return _pickSavePath(
      title: 'Save protected catalogue backup',
      filter: 'Crimson Backup (*.json)|*.json|All Files (*.*)|*.*',
      suggestedName: suggestedName,
      defaultExtension: 'json',
    );
  }

  Future<String?> pickExcelSavePath(
      {String suggestedName = 'crimson_catalogue_export.xlsx'}) async {
    final safeName = suggestedName.replaceAll("'", "''");
    final output = await _runDialog('''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$dialog = New-Object System.Windows.Forms.SaveFileDialog
\$dialog.Title = 'Save Excel export'
\$dialog.Filter = 'Excel Workbook (*.xlsx)|*.xlsx|All Files (*.*)|*.*'
\$dialog.FileName = '$safeName'
\$dialog.DefaultExt = 'xlsx'
\$dialog.AddExtension = \$true
\$dialog.OverwritePrompt = \$true
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dialog.FileName
}
''');
    return output;
  }

  Future<String?> pickPngSavePath(
      {String suggestedName = 'crimson_product_spotlight.png'}) async {
    return _pickSavePath(
      title: 'Save product spotlight image',
      filter: 'PNG Image (*.png)|*.png|All Files (*.*)|*.*',
      suggestedName: suggestedName,
      defaultExtension: 'png',
    );
  }

  Future<String?> pickHtmlSavePath(
      {String suggestedName = 'crimson_product_spotlight.html'}) async {
    return _pickSavePath(
      title: 'Save PDF-ready catalogue page',
      filter: 'HTML Page (*.html)|*.html|All Files (*.*)|*.*',
      suggestedName: suggestedName,
      defaultExtension: 'html',
    );
  }

  Future<String?> pickPdfSavePath(
      {String suggestedName = 'crimson_product_spotlight.pdf'}) async {
    return _pickSavePath(
      title: 'Save product catalogue PDF',
      filter: 'PDF Document (*.pdf)|*.pdf|All Files (*.*)|*.*',
      suggestedName: suggestedName,
      defaultExtension: 'pdf',
    );
  }

  Future<List<String>> pickImageFiles() async {
    final output = await _runDialog('''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Title = 'Select product images'
\$dialog.Filter = 'Image Files (*.jpg;*.jpeg;*.png;*.webp;*.bmp)|*.jpg;*.jpeg;*.png;*.webp;*.bmp|All Files (*.*)|*.*'
\$dialog.Multiselect = \$true
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  foreach (\$file in \$dialog.FileNames) {
    Write-Output \$file
  }
}
''');
    if (output == null) return const [];
    return output
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<String?> _runDialog(String command) async {
    if (!Platform.isWindows) return null;

    final result = await Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      throw FileSystemException(
          'Windows file dialog failed', result.stderr.toString());
    }

    final path = result.stdout.toString().trim();
    return path.isEmpty ? null : path;
  }

  Future<String?> _pickSavePath({
    required String title,
    required String filter,
    required String suggestedName,
    required String defaultExtension,
  }) async {
    final safeTitle = title.replaceAll("'", "''");
    final safeFilter = filter.replaceAll("'", "''");
    final safeName = suggestedName.replaceAll("'", "''");
    final safeExtension = defaultExtension.replaceAll("'", "''");
    return _runDialog('''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$dialog = New-Object System.Windows.Forms.SaveFileDialog
\$dialog.Title = '$safeTitle'
\$dialog.Filter = '$safeFilter'
\$dialog.FileName = '$safeName'
\$dialog.DefaultExt = '$safeExtension'
\$dialog.AddExtension = \$true
\$dialog.OverwritePrompt = \$true
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dialog.FileName
}
''');
  }
}
