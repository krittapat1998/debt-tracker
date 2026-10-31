package com.krittapat.debt_tracker

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.TimeUnit

/** Home-screen widget: total debt and the nearest due date. */
class DebtWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.debt_widget).apply {
                setTextViewText(R.id.total_debt, widgetData.getString("total_debt", null) ?: "฿0.00")
                setTextViewText(
                    R.id.due_month,
                    context.getString(R.string.widget_due_month, widgetData.getString("due_month", null) ?: "-"),
                )

                val name = widgetData.getString("next_due_name", null)
                val date = widgetData.getString("next_due_date", null).orEmpty()
                val amount = widgetData.getString("next_due_amount", null).orEmpty()
                val days = relativeDays(context, widgetData.getString("next_due_iso", null))
                if (name == null) {
                    setTextViewText(R.id.next_due_name, context.getString(R.string.widget_open_app))
                    setViewVisibility(R.id.next_due_detail, View.GONE)
                } else {
                    setTextViewText(R.id.next_due_name, name)
                    val detail = listOf(date, days, amount).filter { it.isNotEmpty() }.joinToString(" · ")
                    setTextViewText(R.id.next_due_detail, detail)
                    setViewVisibility(R.id.next_due_detail, if (detail.isEmpty()) View.GONE else View.VISIBLE)
                }
                setTextViewText(R.id.updated_at, widgetData.getString("updated_at", null).orEmpty())
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** Recomputed on every refresh so "in 3 days" does not go stale. */
    private fun relativeDays(context: Context, iso: String?): String {
        if (iso.isNullOrEmpty()) return ""
        val due = try {
            SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(iso)
        } catch (_: Exception) {
            null
        } ?: return ""
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val days = Math.round((due.time - today.timeInMillis) / TimeUnit.DAYS.toMillis(1).toDouble()).toInt()
        return when {
            days == 0 -> context.getString(R.string.widget_today)
            days == 1 -> context.getString(R.string.widget_tomorrow)
            days < 0 -> context.getString(R.string.widget_overdue, -days)
            else -> context.getString(R.string.widget_in_days, days)
        }
    }
}
