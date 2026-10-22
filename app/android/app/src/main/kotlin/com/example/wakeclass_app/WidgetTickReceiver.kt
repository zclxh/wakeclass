package com.example.wakeclass_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 小组件每分钟刷新：更新「还有多久上课 / 多久下课」，并在跨天时重新计算。
 * 由 [CourseWidgetProvider.scheduleTick] 通过 AlarmManager 触发。
 */
class WidgetTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        CourseWidgetProvider.updateAll(context)
        CourseWidgetProvider.scheduleTick(context)
    }
}
