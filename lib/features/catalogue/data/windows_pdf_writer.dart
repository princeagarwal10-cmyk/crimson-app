import 'dart:io';

/// Converts into a private temporary file before publishing to the save path.
/// Browser output and cleanup must never truncate or invalidate an existing PDF.
class WindowsPdfWriter {
  const WindowsPdfWriter();

  Future<void> write({
    required String edgeExecutable,
    required File html,
    required Directory temporary,
    required String path,
  }) async {
    final generated = File('${temporary.path}/generated.pdf');
    final profile = Directory('${temporary.path}/edge-profile');
    await profile.create(recursive: true);
    final result = await Process.run(
      edgeExecutable,
      [
        '--headless=new',
        '--disable-gpu',
        '--allow-file-access-from-files',
        '--no-pdf-header-footer',
        '--user-data-dir=${profile.path}',
        '--print-to-pdf=${generated.path}',
        html.absolute.uri.toString(),
      ],
      runInShell: false,
    );
    // The newly created PDF is the success criterion. Some Edge versions
    // report a shutdown error even after successfully writing the document.
    if (!await _isPdf(generated)) {
      final diagnostic = result.stderr.toString().trim();
      throw FileSystemException(
        'PDF generation failed (Edge exit ${result.exitCode}). '
        '${diagnostic.isEmpty ? 'The converter did not produce a valid PDF.' : diagnostic}',
        path,
      );
    }

    final destination = File(path).absolute;
    Directory? staged;
    try {
      await destination.parent.create(recursive: true);
      staged = await destination.parent.createTemp('.crimson-pdf-save-');
      final complete = await generated.copy('${staged.path}/complete.pdf');
      // Copy fully on the destination drive, then rename. A generation or copy
      // failure leaves a previously saved catalogue untouched.
      await complete.rename(destination.path);
    } on FileSystemException catch (error) {
      throw FileSystemException(
        'The PDF was generated, but could not be saved. '
        'Close any open copy of this PDF, or choose a new filename in a '
        'writable folder. ${error.osError?.message ?? error.message}',
        destination.path,
        error.osError,
      );
    } finally {
      if (staged != null) await cleanup(staged);
    }
  }

  Future<bool> _isPdf(File file) async {
    if (!await file.exists() || await file.length() < 5) return false;
    final reader = await file.open();
    try {
      return String.fromCharCodes(await reader.read(5)) == '%PDF-';
    } finally {
      await reader.close();
    }
  }

  /// Edge can briefly retain handles in its disposable profile after exiting.
  /// This must not turn a successful export into a reported failure, nor hide
  /// the original conversion/save error.
  static Future<void> cleanup(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Leave this unique temporary directory for normal OS temp cleanup.
    }
  }
}
