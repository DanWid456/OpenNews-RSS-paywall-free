package ch.dawisoft.opennews

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/**
 * Homescreen-Widget: Liste der neuesten frei lesbaren Artikel.
 * Die Daten schreibt die Flutter-App nach jeder Aktualisierung unter dem
 * Schlüssel "widget_articles" (JSON-Liste mit t = Titel, s = Quelle/Zeit,
 * l = Link).
 */
class NewsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.news_widget)

            val service = Intent(context, NewsWidgetService::class.java)
            service.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            service.data = Uri.parse(service.toUri(Intent.URI_INTENT_SCHEME))
            views.setRemoteAdapter(R.id.widget_list, service)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)

            // Kopfzeile und Leertext öffnen die App.
            val open = Intent(context, MainActivity::class.java)
            open.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            val openPending = PendingIntent.getActivity(
                context, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_header, openPending)
            views.setOnClickPendingIntent(R.id.widget_empty, openPending)

            // Ein Tipp auf einen Artikel startet die App mit dessen Link.
            // Die App öffnet ihn dann und markiert ihn als gelesen.
            val item = Intent(context, MainActivity::class.java)
            item.action = "es.antonborri.home_widget.action.LAUNCH"
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_MUTABLE
            }
            views.setPendingIntentTemplate(
                R.id.widget_list,
                PendingIntent.getActivity(context, 1, item, flags)
            )

            appWidgetManager.updateAppWidget(id, views)
        }
        @Suppress("DEPRECATION")
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_list)
    }
}

class NewsWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return NewsWidgetFactory(applicationContext)
    }
}

private class WidgetArticle(val title: String, val meta: String, val link: String)

private class NewsWidgetFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private var items: List<WidgetArticle> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val loaded = ArrayList<WidgetArticle>()
        try {
            val raw = HomeWidgetPlugin.getData(context)
                .getString("widget_articles", "[]") ?: "[]"
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val o = array.getJSONObject(i)
                loaded.add(
                    WidgetArticle(
                        o.optString("t"),
                        o.optString("s"),
                        o.optString("l")
                    )
                )
            }
        } catch (e: Exception) {
            // Unlesbare Daten: Widget bleibt leer.
        }
        items = loaded
    }

    override fun onDestroy() {}

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.news_widget_item)
        if (position < 0 || position >= items.size) return views
        val a = items[position]
        views.setTextViewText(R.id.item_title, a.title)
        views.setTextViewText(R.id.item_meta, a.meta)
        val fill = Intent()
        fill.data = Uri.parse(a.link)
        views.setOnClickFillInIntent(R.id.item_root, fill)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}
