package com.example.wakeclass_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

class MainActivity : FlutterActivity() {
    private companion object {
        /** 单个导入文件最多读 8 MB（课表页 HTML 一般 200 KB 上下）。 */
        const val MAX_IMPORT_BYTES = 8 * 1024 * 1024

        const val REQUEST_PICK_FILE = 0x7A11
    }

    private var importChannel: MethodChannel? = null

    /** 冷启动时由 intent 带进来的文本，等 Dart 调 takePending 取走。 */
    private var pendingText: String? = null

    /** 选文件请求的 Flutter 回调（同一时间只允许一个）。 */
    private var pickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Flutter ↔ 原生：刷新桌面小组件 / 一键把小组件添加到桌面
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "wakeclass/widget",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> {
                    CourseWidgetProvider.updateAll(this)
                    CourseWidgetProvider.scheduleTick(this)
                    result.success(true)
                }

                "pinWidget" -> {
                    val size = call.argument<String>("size") ?: "small"
                    result.success(pinWidget(size))
                }

                "openHome" -> {
                    result.success(openHome())
                }

                else -> result.notImplemented()
            }
        }

        // 外部导入：微信/QQ 里「用其他应用打开」、系统分享、App 内选文件
        if (pendingText == null) pendingText = textFromIntent(intent)
        importChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "wakeclass/import",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePending" -> {
                        val text = pendingText
                        pendingText = null
                        // 内容取走后把 intent 清成普通启动，避免下次从后台回来重复导入
                        if (text != null) setIntent(Intent(Intent.ACTION_MAIN))
                        result.success(text)
                    }

                    "pickFile" -> openFilePicker(result)

                    "shareText" -> {
                        val text = call.argument<String>("text")
                        result.success(!text.isNullOrBlank() && shareText(text))
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    /** App 已在运行（singleTop）时又收到「打开 / 分享」：直接推给 Dart。 */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = textFromIntent(intent) ?: return
        val channel = importChannel
        if (channel == null) {
            pendingText = text
        } else {
            channel.invokeMethod("incoming", text)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_FILE) return
        val pending = pickResult
        pickResult = null
        val uri = if (resultCode == RESULT_OK) data?.data else null
        pending?.success(if (uri == null) null else readUri(uri))
    }

    // ---------- 外部内容 → 文本 ----------

    private fun textFromIntent(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { readUri(it) }
            Intent.ACTION_SEND -> {
                val stream = streamOf(intent)
                if (stream != null) {
                    readUri(stream)
                } else {
                    // 只带文字的分享：太短的多半是网页链接，忽略
                    val shared = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (shared != null && shared.length >= 64) shared else null
                }
            }

            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun readUri(uri: Uri): String? = try {
        contentResolver.openInputStream(uri)?.use { stream ->
            decodeText(readAll(stream))
        }
    } catch (_: Exception) {
        null
    }

    private fun readAll(stream: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        val chunk = ByteArray(32 * 1024)
        var total = 0
        while (total < MAX_IMPORT_BYTES) {
            val read = stream.read(chunk)
            if (read <= 0) break
            out.write(chunk, 0, read)
            total += read
        }
        return out.toByteArray()
    }

    /** 优先 UTF-8，出现非法字节时回退 GBK（不少教务系统页面仍是 GBK）。 */
    private fun decodeText(bytes: ByteArray): String {
        if (bytes.isEmpty()) return ""
        try {
            val decoder = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            return decoder.decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) {
            // 不是合法 UTF-8：继续试 GBK
        }
        return try {
            String(bytes, charset("GBK"))
        } catch (_: Exception) {
            String(bytes, Charsets.UTF_8)
        }
    }

    // ---------- App 内选文件 / 分享 ----------

    private fun openFilePicker(result: MethodChannel.Result) {
        if (pickResult != null) {
            result.error("busy", "已有文件选择窗口", null)
            return
        }
        pickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("text/*", "application/json", "application/octet-stream"),
            )
        }
        try {
            startActivityForResult(intent, REQUEST_PICK_FILE)
        } catch (e: Exception) {
            pickResult = null
            result.error("no_picker", e.message ?: "无法打开文件选择器", null)
        }
    }

    private fun shareText(text: String): Boolean = try {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        startActivity(Intent.createChooser(send, "发送到电脑"))
        true
    } catch (_: Exception) {
        false
    }

    // ---------- 小组件 ----------

    /** 回到系统桌面（微信 / MIUI 等桌面不支持一键添加时的手动引导）。 */
    private fun openHome(): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 请求把指定尺寸的小组件固定到桌面（Android 8+，由系统弹窗确认）。 */
    private fun pinWidget(size: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val manager = AppWidgetManager.getInstance(this)
            if (!manager.isRequestPinAppWidgetSupported) return false
            val provider = when (size) {
                "medium" -> CourseWidgetMedium::class.java
                "large" -> CourseWidgetLarge::class.java
                else -> CourseWidgetSmall::class.java
            }
            manager.requestPinAppWidget(ComponentName(this, provider), null, null)
        } catch (_: Exception) {
            false
        }
    }
}
