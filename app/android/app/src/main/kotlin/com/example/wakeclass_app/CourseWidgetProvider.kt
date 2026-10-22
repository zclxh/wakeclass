package com.example.wakeclass_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * 醒课桌面小组件。
 *
 * 数据来源：Flutter shared_preferences 写入的课表 JSON
 * （文件 FlutterSharedPreferences，键 flutter.wakeclass_schedule_v1）。
 *
 * 展示规则：
 * - 顶部 1/5：左边自定义文字（≤6 字），右边「10.22 第8周 周四」；
 * - 下方 4/5：今天还没上完的课程，按数量平均等分（小 3 门 / 中 5 门 / 大 7 门）；
 * - 每节课显示「距上课还有多久」或「距下课还有多久」；
 * - 今天的课上完后显示「(〃'▽'〃) 今天没有课啦」；
 * - 每分钟刷新一次，跨天后自动重新计算。
 */
abstract class CourseWidgetProvider : AppWidgetProvider() {

    /** 该尺寸最多展示几门未结束的课程。 */
    abstract val maxCourses: Int

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            try {
                appWidgetManager.updateAppWidget(id, render(context))
            } catch (_: Exception) {
                // 单个小组件刷新失败不影响其他实例
            }
        }
        scheduleTick(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleTick(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        scheduleTick(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            updateAll(context)
            scheduleTick(context)
        }
    }

    /** 生成当前时刻的小组件界面。 */
    fun render(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.course_widget)
        val prefs = prefs(context)
        val colorIndex = readInt(prefs, KEY_COLOR, 0).coerceIn(0, BG_IDS.size - 1)
        val palette = PALETTES[colorIndex]
        for (i in BG_IDS.indices) {
            views.setViewVisibility(BG_IDS[i], if (i == colorIndex) View.VISIBLE else View.GONE)
        }

        val now = Calendar.getInstance()
        val json = loadSchedule(prefs)
        val week = json?.let { parseTermStart(it) }?.let { weekOf(it, now) }
        val totalWeeks = json?.optInt("total_weeks", 20) ?: 20
        val inTerm = week != null && week in 1..totalWeeks

        // 顶部：左上自定义文字 + 右上日期/周次/周几
        views.setTextViewText(R.id.widget_title, resolveTitle(prefs, json))
        views.setTextColor(R.id.widget_title, palette.text)
        views.setTextViewText(R.id.widget_date, dateText(now, week))
        views.setTextColor(R.id.widget_date, palette.accent)

        val nowMinute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val remaining = if (inTerm) {
            todayCourses(context, now).filter { it.endMinute > nowMinute }
        } else {
            emptyList()
        }

        if (remaining.isEmpty()) {
            views.setViewVisibility(R.id.widget_rows, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            val hasFace = json != null && inTerm
            views.setTextViewText(R.id.widget_empty_face, if (hasFace) "(〃'▽'〃)" else "醒课")
            views.setTextColor(R.id.widget_empty_face, palette.muted)
            views.setTextViewText(
                R.id.widget_empty_text,
                when {
                    json == null -> "打开醒课导入课表"
                    !inTerm -> "假期愉快 🌴"
                    else -> "今天没有课啦"
                },
            )
            views.setTextColor(R.id.widget_empty_text, palette.text)
        } else {
            views.setViewVisibility(R.id.widget_empty, View.GONE)
            views.setViewVisibility(R.id.widget_rows, View.VISIBLE)
            views.removeAllViews(R.id.widget_rows)
            val shown = remaining.take(maxCourses)
            shown.forEachIndexed { index, course ->
                val row = RemoteViews(context.packageName, R.layout.course_widget_row)
                row.setTextViewText(R.id.row_name, course.name)
                row.setTextColor(R.id.row_name, palette.text)
                row.setTextViewText(R.id.row_status, statusText(course, nowMinute))
                row.setTextColor(R.id.row_status, palette.accent)
                row.setTextViewText(R.id.row_detail, course.detail())
                row.setTextColor(R.id.row_detail, palette.muted)
                row.setViewVisibility(
                    R.id.row_divider,
                    if (index == 0) View.GONE else View.VISIBLE,
                )
                views.addView(R.id.widget_rows, row)
            }
        }

        val launch = Intent(context, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
        return views
    }

    companion object {
        const val ACTION_REFRESH = "com.example.wakeclass_app.WIDGET_REFRESH"
        const val ACTION_TICK = "com.example.wakeclass_app.WIDGET_TICK"

        private const val TICK_REQUEST_CODE = 1001
        private const val TICK_INTERVAL_MS = 60_000L

        private const val KEY_SCHEDULE = "flutter.wakeclass_schedule_v1"
        private const val KEY_TITLE = "flutter.wakeclass_widget_title"
        private const val KEY_COLOR = "flutter.wakeclass_widget_color"

        /** 节次开始时间（与 core 的 defaultPeriodTimes 一致）。 */
        private val PERIOD_START = arrayOf(
            "08:00", "08:55", "10:10", "11:05", "14:00", "14:55",
            "16:10", "17:05", "19:00", "19:55", "20:50", "21:45",
        )

        /** 节次结束时间。 */
        private val PERIOD_END = arrayOf(
            "08:45", "09:40", "10:55", "11:50", "14:45", "15:40",
            "16:55", "17:50", "19:45", "20:40", "21:35", "22:30",
        )

        private val BG_IDS = intArrayOf(
            R.id.widget_bg_0, R.id.widget_bg_1, R.id.widget_bg_2, R.id.widget_bg_3,
            R.id.widget_bg_4, R.id.widget_bg_5, R.id.widget_bg_6, R.id.widget_bg_7,
        )

        /** 与 Flutter 端 widgetColorPresets 顺序一致。 */
        private val PALETTES = arrayOf(
            WidgetPalette(0xFF3E2C1C.toInt(), 0xFFB0652A.toInt(), 0xFF8A7460.toInt()),
            WidgetPalette(0xFF16352F.toInt(), 0xFF00796B.toInt(), 0xFF5E7F78.toInt()),
            WidgetPalette(0xFF16283C.toInt(), 0xFF1565C0.toInt(), 0xFF5C7AA3.toInt()),
            WidgetPalette(0xFF3E2E0F.toInt(), 0xFFE07B00.toInt(), 0xFF8A7448.toInt()),
            WidgetPalette(0xFF3C1524.toInt(), 0xFFC2185B.toInt(), 0xFF8C5F71.toInt()),
            WidgetPalette(0xFF2A1538.toInt(), 0xFF6A1B9A.toInt(), 0xFF7A6A8C.toInt()),
            WidgetPalette(0xFF17301A.toInt(), 0xFF2E7D32.toInt(), 0xFF5C7A5F.toInt()),
            WidgetPalette(0xFF1E2529.toInt(), 0xFF37474F.toInt(), 0xFF66757D.toInt()),
        )

        private class SizeSpec(
            val clazz: Class<out CourseWidgetProvider>,
            val factory: () -> CourseWidgetProvider,
        )

        private val SIZE_SPECS = listOf(
            SizeSpec(CourseWidgetSmall::class.java) { CourseWidgetSmall() },
            SizeSpec(CourseWidgetMedium::class.java) { CourseWidgetMedium() },
            SizeSpec(CourseWidgetLarge::class.java) { CourseWidgetLarge() },
        )

        /** 刷新全部尺寸、全部实例（App 内数据/配置变化后调用）。 */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (spec in SIZE_SPECS) {
                val ids = manager.getAppWidgetIds(ComponentName(context, spec.clazz))
                if (ids.isEmpty()) continue
                val provider = spec.factory()
                for (id in ids) {
                    try {
                        manager.updateAppWidget(id, provider.render(context))
                    } catch (_: Exception) {
                        // 忽略单个实例失败
                    }
                }
            }
        }

        /** 安排下一次刷新（还有课 → 每分钟；今天没课了 → 次日 00:05）。 */
        fun scheduleTick(context: Context) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return
            val pending = tickIntent(context)
            manager.cancel(pending)
            if (!hasAnyWidget(context)) return
            val now = Calendar.getInstance()
            val delay = if (hasRemainingToday(context, now)) {
                TICK_INTERVAL_MS - (System.currentTimeMillis() % TICK_INTERVAL_MS)
            } else {
                millisUntilTomorrow(now)
            }
            val triggerAt = System.currentTimeMillis() + delay
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    manager.setAndAllowWhileIdle(AlarmManager.RTC, triggerAt, pending)
                } else {
                    manager.set(AlarmManager.RTC, triggerAt, pending)
                }
            } catch (_: Exception) {
                // 部分机型限制精确闹钟，忽略
            }
        }

        private fun tickIntent(context: Context): PendingIntent {
            val intent = Intent(context, WidgetTickReceiver::class.java)
                .setAction(ACTION_TICK)
            return PendingIntent.getBroadcast(
                context,
                TICK_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
            )
        }

        private fun immutableFlag(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }

        private fun hasAnyWidget(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return SIZE_SPECS.any {
                manager.getAppWidgetIds(ComponentName(context, it.clazz)).isNotEmpty()
            }
        }

        private fun hasRemainingToday(context: Context, now: Calendar): Boolean {
            val nowMinute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            return todayCourses(context, now).any { it.endMinute > nowMinute }
        }

        private fun millisUntilTomorrow(now: Calendar): Long {
            val next = (now.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 5)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            return (next.timeInMillis - now.timeInMillis).coerceAtLeast(TICK_INTERVAL_MS)
        }

        private fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        private fun loadSchedule(prefs: SharedPreferences): JSONObject? {
            val raw = prefs.getString(KEY_SCHEDULE, null) ?: return null
            return try {
                JSONObject(raw)
            } catch (_: Exception) {
                null
            }
        }

        private fun readInt(prefs: SharedPreferences, key: String, fallback: Int): Int {
            return try {
                when (val value = prefs.all[key]) {
                    is Int -> value
                    is Long -> value.toInt()
                    is String -> value.toIntOrNull() ?: fallback
                    else -> fallback
                }
            } catch (_: Exception) {
                fallback
            }
        }

        /** 左上角自定义文字：用户没设置时用课表标题（最多 6 字）。 */
        private fun resolveTitle(prefs: SharedPreferences, json: JSONObject?): String {
            val custom = prefs.getString(KEY_TITLE, null)?.trim().orEmpty()
            if (custom.isNotEmpty()) return takeChars(custom, 6)
            val title = json?.optString("title").orEmpty().trim()
            if (title.isNotEmpty()) return takeChars(title, 6)
            return "醒课"
        }

        private fun takeChars(text: String, limit: Int): String {
            if (text.isEmpty()) return text
            val end = text.offsetByCodePoints(0, text.codePointCount(0, text.length).coerceAtMost(limit))
            return text.substring(0, end)
        }

        /** 今天的课程（含已结束的），按开始时间排序。 */
        fun todayCourses(context: Context, now: Calendar): List<WidgetCourse> {
            val json = loadSchedule(prefs(context)) ?: return emptyList()
            val start = parseTermStart(json) ?: return emptyList()
            val week = weekOf(start, now) ?: return emptyList()
            if (week < 1 || week > json.optInt("total_weeks", 20)) return emptyList()
            val dow = dayOfWeek(now)
            val array = json.optJSONArray("courses") ?: return emptyList()
            val result = mutableListOf<WidgetCourse>()
            for (i in 0 until array.length()) {
                val course = array.optJSONObject(i) ?: continue
                if (course.optInt("day_of_week", 0) != dow) continue
                if (!includesWeek(course, week)) continue
                val startIndex = (course.optInt("start_period", 0) - 1)
                    .coerceIn(0, PERIOD_START.size - 1)
                val endIndex = (course.optInt("end_period", 0) - 1)
                    .coerceIn(startIndex, PERIOD_END.size - 1)
                result.add(
                    WidgetCourse(
                        name = course.optString("name").ifBlank { "（未命名课程）" },
                        location = course.optString("location"),
                        startMinute = minuteOf(PERIOD_START[startIndex]),
                        endMinute = minuteOf(PERIOD_END[endIndex]),
                        timeText = "${PERIOD_START[startIndex]}-${PERIOD_END[endIndex]}",
                    ),
                )
            }
            result.sortBy { it.startMinute }
            return result
        }

        private fun includesWeek(course: JSONObject, week: Int): Boolean {
            val weeks = course.optJSONArray("weeks") ?: return true
            if (weeks.length() == 0) return true
            for (i in 0 until weeks.length()) {
                if (weeks.optInt(i, -1) == week) return true
            }
            return false
        }

        private fun minuteOf(hhmm: String): Int {
            val parts = hhmm.split(":")
            if (parts.size != 2) return 0
            return (parts[0].toIntOrNull() ?: 0) * 60 + (parts[1].toIntOrNull() ?: 0)
        }

        private fun parseTermStart(json: JSONObject): Calendar? {
            val raw = json.optString("term_start")
            if (raw.isBlank()) return null
            val parts = raw.split("-")
            if (parts.size != 3) return null
            val year = parts[0].toIntOrNull() ?: return null
            val month = parts[1].toIntOrNull() ?: return null
            val day = parts[2].toIntOrNull() ?: return null
            return Calendar.getInstance().apply {
                set(year, month - 1, day, 0, 0, 0)
                set(Calendar.MILLISECOND, 0)
            }
        }

        /** 第几周；学期还没开始时返回 0。 */
        private fun weekOf(termStart: Calendar, now: Calendar): Int? {
            val startDay = startOfDay(termStart)
            val today = startOfDay(now)
            val days = ((today.timeInMillis - startDay.timeInMillis) / 86_400_000L).toInt()
            return days / 7 + 1
        }

        private fun startOfDay(calendar: Calendar): Calendar =
            (calendar.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

        /** Dart 风格星期（周一 = 1 … 周日 = 7）。 */
        private fun dayOfWeek(calendar: Calendar): Int {
            val value = calendar.get(Calendar.DAY_OF_WEEK)
            return if (value == Calendar.SUNDAY) 7 else value - 1
        }

        private fun weekdayCn(calendar: Calendar): String {
            val names = arrayOf("周日", "周一", "周二", "周三", "周四", "周五", "周六")
            return names[calendar.get(Calendar.DAY_OF_WEEK) - 1]
        }

        /** 「10.22 第8周 周四」 */
        private fun dateText(now: Calendar, week: Int?): String {
            val month = now.get(Calendar.MONTH) + 1
            val day = now.get(Calendar.DAY_OF_MONTH)
            val weekday = weekdayCn(now)
            if (week == null || week < 1) return "$month.$day $weekday"
            return String.format(Locale.US, "%d.%d 第%d周 %s", month, day, week, weekday)
        }

        /** 课前 / 课中倒计时文案。 */
        fun statusText(course: WidgetCourse, nowMinute: Int): String {
            return if (nowMinute < course.startMinute) {
                countdownText(course.startMinute - nowMinute, "上课")
            } else {
                countdownText(course.endMinute - nowMinute, "下课")
            }
        }

        private fun countdownText(left: Int, verb: String): String {
            if (left <= 1) return if (verb == "上课") "马上上课" else "即将下课"
            if (left < 60) return "还有 $left 分钟$verb"
            val hours = left / 60
            val rest = left % 60
            return if (rest == 0) "还有 $hours 小时$verb" else "还有 $hours 小时 $rest 分$verb"
        }
    }
}

/** 小尺寸 4×2：3 门课。 */
class CourseWidgetSmall : CourseWidgetProvider() {
    override val maxCourses: Int get() = 3
}

/** 中尺寸 4×4：5 门课。 */
class CourseWidgetMedium : CourseWidgetProvider() {
    override val maxCourses: Int get() = 5
}

/** 大尺寸 4×5：7 门课。 */
class CourseWidgetLarge : CourseWidgetProvider() {
    override val maxCourses: Int get() = 7
}

/** 小组件里的一节课。 */
data class WidgetCourse(
    val name: String,
    val location: String,
    val startMinute: Int,
    val endMinute: Int,
    val timeText: String,
) {
    /** 第二行：时间 · 地点。 */
    fun detail(): String = if (location.isBlank()) timeText else "$timeText · $location"
}

/** 配色：正文 / 强调色 / 次要文字（背景由布局里的 8 层 View 切换）。 */
data class WidgetPalette(
    val text: Int,
    val accent: Int,
    val muted: Int,
)
