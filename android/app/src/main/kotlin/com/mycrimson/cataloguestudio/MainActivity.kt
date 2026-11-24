package com.mycrimson.cataloguestudio

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val pickImagesRequestCode = 4105
    private val pickStockWorkbookRequestCode = 4106
    private var pendingImagePickResult: MethodChannel.Result? = null
    private var pendingStockWorkbookResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mycrimson.cataloguestudio/storage"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(filesDir.absolutePath)
                "pickImageFiles" -> pickImageFiles(result)
                "pickStockWorkbook" -> pickStockWorkbook(result)
                "createPdfFromImages" -> createPdfFromImages(call.argument<List<String>>("imagePaths").orEmpty(), call.argument<String>("outputPath"), result)
                "shareFiles" -> shareFiles(call.argument<List<String>>("paths").orEmpty(), call.argument<String>("mimeType").orEmpty(), call.argument<String>("title").orEmpty(), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun pickStockWorkbook(result: MethodChannel.Result) {
        if (pendingStockWorkbookResult != null) {
            result.error("PICKER_BUSY", "A stock workbook picker is already open.", null)
            return
        }
        pendingStockWorkbookResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "application/octet-stream"
            ))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(Intent.createChooser(intent, "Select Tally stock workbook"), pickStockWorkbookRequestCode)
        } catch (error: Exception) {
            pendingStockWorkbookResult = null
            result.error("PICK_WORKBOOK_FAILED", error.message, null)
        }
    }

    private fun pickImageFiles(result: MethodChannel.Result) {
        if (pendingImagePickResult != null) {
            result.error("PICKER_BUSY", "Image picker is already open.", null)
            return
        }

        pendingImagePickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(Intent.createChooser(intent, "Select product photos"), pickImagesRequestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickStockWorkbookRequestCode) {
            val result = pendingStockWorkbookResult
            pendingStockWorkbookResult = null
            if (result == null) return
            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri == null) {
                result.success(null)
                return
            }
            try {
                val target = File.createTempFile("tally_stock_", ".xlsx", cacheDir)
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                } ?: throw IllegalStateException("Could not read the selected file.")
                result.success(target.absolutePath)
            } catch (error: Exception) {
                result.error("PICK_WORKBOOK_FAILED", error.message, null)
            }
            return
        }
        if (requestCode != pickImagesRequestCode) return

        val result = pendingImagePickResult
        pendingImagePickResult = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }

        try {
            val uris = mutableListOf<Uri>()
            val clipData = data.clipData
            if (clipData != null) {
                for (index in 0 until clipData.itemCount) {
                    uris.add(clipData.getItemAt(index).uri)
                }
            } else {
                data.data?.let { uris.add(it) }
            }

            val pickedDir = File(filesDir, "picked_images")
            pickedDir.mkdirs()
            val paths = uris.mapIndexedNotNull { index, uri ->
                copyPickedImage(uri, pickedDir, index)
            }
            result.success(paths)
        } catch (error: Exception) {
            result.error("PICK_IMAGE_FAILED", error.message, null)
        }
    }

    private fun copyPickedImage(uri: Uri, targetDir: File, index: Int): String? {
        val extension = extensionFor(uri)
        val target = File(targetDir, "picked_${System.currentTimeMillis()}_${index}${extension}")
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: return null
        return target.absolutePath
    }

    private fun extensionFor(uri: Uri): String {
        val mime = contentResolver.getType(uri).orEmpty().lowercase()
        return when {
            mime.contains("png") -> ".png"
            mime.contains("webp") -> ".webp"
            mime.contains("bmp") -> ".bmp"
            else -> ".jpg"
        }
    }
    private fun createPdfFromImages(imagePaths: List<String>, outputPath: String?, result: MethodChannel.Result) {
        if (imagePaths.isEmpty() || outputPath.isNullOrBlank()) {
            result.error("PDF_INPUT", "Catalogue pages or output path are missing.", null)
            return
        }
        try {
            val document = PdfDocument()
            imagePaths.forEachIndexed { index, imagePath ->
                val bitmap = BitmapFactory.decodeFile(imagePath)
                    ?: throw IllegalArgumentException("Could not read catalogue page: $imagePath")
                val pageInfo = PdfDocument.PageInfo.Builder(1240, 1754, index + 1).create()
                val page = document.startPage(pageInfo)
                page.canvas.drawColor(Color.WHITE)
                val scale = minOf(1240f / bitmap.width, 1754f / bitmap.height)
                val width = bitmap.width * scale
                val height = bitmap.height * scale
                val target = RectF((1240f - width) / 2f, (1754f - height) / 2f, (1240f + width) / 2f, (1754f + height) / 2f)
                page.canvas.drawBitmap(bitmap, null, target, null)
                document.finishPage(page)
                bitmap.recycle()
            }
            val target = File(outputPath)
            target.parentFile?.mkdirs()
            target.outputStream().use(document::writeTo)
            document.close()
            result.success(target.absolutePath)
        } catch (error: Exception) {
            result.error("PDF_FAILED", error.message, null)
        }
    }

    private fun shareFiles(paths: List<String>, mimeType: String, title: String, result: MethodChannel.Result) {
        if (paths.isEmpty()) {
            result.error("SHARE_INPUT", "No catalogue files were supplied.", null)
            return
        }
        try {
            val shareDir = File(cacheDir, "shared").apply { mkdirs() }
            val uris = ArrayList<Uri>()
            paths.forEachIndexed { index, path ->
                val source = File(path)
                if (!source.exists()) throw IllegalArgumentException("File not found: $path")
                val target = File(shareDir, "${System.currentTimeMillis()}_${index}_${source.name}")
                source.copyTo(target, overwrite = true)
                uris.add(FileProvider.getUriForFile(this, "$packageName.fileprovider", target))
            }
            val intent = Intent(if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).apply {
                type = mimeType.ifBlank { "application/octet-stream" }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newUri(contentResolver, "Crimson catalogue", uris.first())
                if (uris.size == 1) {
                    putExtra(Intent.EXTRA_STREAM, uris.first())
                } else {
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                }
            }
            startActivity(Intent.createChooser(intent, title.ifBlank { "Share Crimson catalogue" }))
            result.success(true)
        } catch (error: Exception) {
            result.error("SHARE_FAILED", error.message, null)
        }
    }
}


