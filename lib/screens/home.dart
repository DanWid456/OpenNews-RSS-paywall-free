import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
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
    return Scaffold(
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
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Feed'),
          NavigationDestination(
              icon: Icon(Icons.bookmark_border),
              selectedIcon: Icon(Icons.bookmark),
              label: 'Gemerkt'),
          NavigationDestination(
              icon: Icon(Icons.rss_feed), label: 'Quellen'),
          NavigationDestination(
              icon: Icon(Icons.tune), label: 'Einstellungen'),
        ],
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

  Widget _tab(String? id, String label) {
    final selected = app.selectedCategory == id;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => app.setCategory(id),
      child: Container(
        height: 44,
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
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
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
                          Text('Heute',
                              style: text.headlineSmall!
                                  .copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            hidden == 0
                                ? 'Nur frei lesbare Artikel'
                                : '$hidden Paywall-Artikel ausgeblendet',
                            style: text.bodySmall!.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Suchen',
                      icon: Icon(searching ? Icons.close : Icons.search),
                      onPressed: _toggleSearch,
                    ),
                    _viewButton(0, Icons.view_headline, 'Kompakte Ansicht'),
                    _viewButton(1, Icons.view_list, 'Magazin-Ansicht'),
                    _viewButton(2, Icons.view_agenda_outlined,
                        'Karten-Ansicht'),
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
                    decoration: const InputDecoration(
                      hintText: 'In Titeln und Anrissen suchen',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: app.setSearch,
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    _tab(null, 'Alle'),
                    for (final id in app.tabs)
                      _tab(id, kCategories[id] ?? id),
                  ],
                ),
              ),
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
                                  (busy
                                      ? 'Artikel werden geladen und geprüft …'
                                      : 'Keine Artikel gefunden. Zum '
                                          'Aktualisieren nach unten ziehen.'),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Gemerkt')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final items = app.bookmarks;
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Noch nichts gemerkt. Artikel lange drücken und '
                  '«Merken» wählen.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, i) => articleTile(items[i], 1),
          );
        },
      ),
    );
  }
}
