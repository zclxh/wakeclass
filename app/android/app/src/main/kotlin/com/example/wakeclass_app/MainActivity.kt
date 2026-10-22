package com.example.wakeclass_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }

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
