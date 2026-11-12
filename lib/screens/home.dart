import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../widgets/tiles.dart';
import 'settings.dart';
import 'sources.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    // Hört auf den App-Zustand, damit die Beschriftungen einem Sprachwechsel
    // folgen.
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) => Scaffold(
        body: IndexedStack(
          index: index,
          children: const [
            FeedScreen(),
            BookmarksScreen(),
            SourcesScreen(),
            SettingsScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: tr('nav_feed')),
            NavigationDestination(
                icon: const Icon(Icons.bookmark_border),
                selectedIcon: const Icon(Icons.bookmark),
                label: tr('nav_saved')),
            NavigationDestination(
                icon: const Icon(Icons.rss_feed), label: tr('nav_sources')),
            NavigationDestination(
                icon: const Icon(Icons.tune), label: tr('nav_settings')),
          ],
        ),
      ),
    );
  }
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final app = AppState.instance;
  final searchController = TextEditingController();
  bool searching = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => searching = !searching);
    if (!searching) {
      searchController.clear();
      app.setSearch('');
    }
  }

  Widget _viewButton(int mode, IconData icon, String tooltip) {
    final selected = app.viewMode == mode;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primaryContainer : null,
        foregroundColor:
            selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
      icon: Icon(icon),
      onPressed: () => app.setViewMode(mode),
    );
  }

  Widget _tab(String? id) {
    final selected = app.selectedCategory == id;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => app.setCategory(id),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                width: 2,
                color: selected ? scheme.primary : Colors.transparent),
          ),
        ),
        child: Text(
          id == null ? tr('all') : tr('cat_$id'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Themen-Reiter: «Alle» zuvorderst, ab fünf Einträgen auf zwei Zeilen
  /// verteilt. Passt eine Zeile nicht in die Breite, lässt sich der Block
  /// seitlich schieben.
  Widget _tabs() {
    final ids = <String?>[null, ...app.tabs];
    final List<List<String?>> rows;
    if (ids.length <= 4) {
      rows = [ids];
    } else {
      final firstRow = (ids.length + 1) ~/ 2;
      rows = [ids.sublist(0, firstRow), ids.sublist(firstRow)];
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Row(children: [for (final id in row) _tab(id)]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final items = app.feed;
        final busy = app.refreshing;
        final hidden = app.hiddenCount;
        return SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('today'),
                              style: text.headlineSmall!
                                  .copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            hidden == 0
                                ? tr('only_free')
                                : tr('hidden_count', {'n': hidden}),
                            style: text.bodySmall!.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr('search'),
                      icon: Icon(searching ? Icons.close : Icons.search),
                      onPressed: _toggleSearch,
                    ),
                    _viewButton(0, Icons.view_headline, tr('view_compact')),
                    _viewButton(1, Icons.view_list, tr('view_magazine')),
                    _viewButton(
                        2, Icons.view_agenda_outlined, tr('view_cards')),
                  ],
                ),
              ),
              if (searching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: tr('search_hint'),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: app.setSearch,
                  ),
                ),
              _tabs(),
              const Divider(),
              if (busy)
                LinearProgressIndicator(
                  minHeight: 2,
                  value: app.checkTotal > 0
                      ? app.checkDone / app.checkTotal
                      : null,
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: app.refresh,
                  child: items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(32),
                          children: [
                            const SizedBox(height: 80),
                            Icon(Icons.article_outlined,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 16),
                            Text(
                              app.lastError ??
                                  (busy ? tr('loading') : tr('empty')),
                              textAlign: TextAlign.center,
                              style: text.bodyLarge,
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.only(
                              top: app.viewMode == 2 ? 6 : 0, bottom: 16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => app.viewMode == 2
                              ? const SizedBox.shrink()
                              : const Divider(),
                          itemBuilder: (_, i) =>
                              articleTile(items[i], app.viewMode),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final items = app.bookmarks;
        return Scaffold(
          appBar: AppBar(title: Text(tr('nav_saved'))),
          body: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(tr('saved_empty'),
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) => articleTile(items[i], 1),
                ),
        );
      },
    );
  }
}
