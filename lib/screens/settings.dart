import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../widgets/pickers.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final app = AppState.instance;
  final mutedController = TextEditingController();

  @override
  void dispose() {
    mutedController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall!
                .copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  // --- Pro ---

  Future<void> _showProDialog() async {
    final price = app.pro.priceLabel;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Pro freischalten'),
        content: Text(
          'Mit Pro fügst du eigene RSS-Feeds hinzu. Einmaliger Kauf, kein '
          'Abo.${price.isEmpty ? '' : '\n\nPreis: $price'}',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialog);
              await app.pro.restore();
              _snack('Frühere Käufe werden geprüft.');
            },
            child: const Text('Kauf wiederherstellen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialog);
              final started = await app.pro.buy();
              if (!started) {
                _snack('Der Kauf ist auf diesem Gerät gerade nicht möglich.');
              }
            },
            child: const Text('Kaufen'),
          ),
        ],
      ),
    );
  }

  // --- Eigene Feeds ---

  Future<void> _editFeed([CustomFeed? existing]) async {
    if (!app.isPro) {
      await _showProDialog();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _FeedDialog(existing: existing),
    );
  }

  Future<void> _importFeeds() async {
    if (!app.isPro) {
      await _showProDialog();
      return;
    }
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Feeds importieren'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'OPML-Text oder eine Feed-Adresse pro Zeile einfügen',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, controller.text),
              child: const Text('Importieren')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    _snack('Feeds werden geprüft …');
    final added = await app.importFeeds(text);
    _snack('$added Feed(s) hinzugefügt.');
  }

  Future<void> _exportFeeds() async {
    await Clipboard.setData(ClipboardData(text: app.exportOpml()));
    _snack('OPML in die Zwischenablage kopiert.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final interests = app.interests.toSet();
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _header('Region'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RegionPicker(
                  country: app.country,
                  language: app.language,
                  onChanged: app.setRegion,
                ),
              ),
              _header('Interessen'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InterestChips(
                  selected: interests,
                  onChanged: (s) {
                    if (s.isEmpty) return;
                    app.setInterests(
                        kCategories.keys.where(s.contains).toList());
                  },
                ),
              ),
              _header('Eigene Feeds (Pro)'),
              if (!app.isPro)
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Pro freischalten'),
                  subtitle: Text(app.pro.priceLabel.isEmpty
                      ? 'Einmaliger Kauf – eigene RSS-Feeds hinzufügen'
                      : 'Einmalig ${app.pro.priceLabel} – eigene RSS-Feeds '
                          'hinzufügen'),
                  onTap: _showProDialog,
                ),
              if (app.isPro)
                for (final f in app.customFeeds)
                  ListTile(
                    title: Text(f.title),
                    subtitle: Text(
                      '${kCategories[f.category] ?? f.category} · '
                      '${f.unfiltered ? 'ungefiltert' : 'Paywall-Filter aktiv'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Feed entfernen',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => app.removeCustomFeed(f),
                    ),
                    onTap: () => _editFeed(f),
                  ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Feed hinzufügen'),
                onTap: () => _editFeed(),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Feeds importieren (OPML)'),
                onTap: _importFeeds,
              ),
              if (app.isPro && app.customFeeds.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Feeds exportieren (OPML)'),
                  onTap: _exportFeeds,
                ),
              _header('Paywall-Filter'),
              SwitchListTile(
                title: const Text('Tiefenprüfung'),
                subtitle: const Text(
                    'Lädt jede Artikelseite einmal, um versteckte '
                    'Bezahlschranken zu erkennen. Aus: schneller und '
                    'weniger Datenverbrauch, aber ungenauer.'),
                value: app.deepCheck,
                onChanged: app.setDeepCheck,
              ),
              _header('Stummgeschaltete Wörter'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: mutedController,
                      decoration: InputDecoration(
                        hintText: 'Wort oder Begriff',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          tooltip: 'Hinzufügen',
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            app.addMutedWord(mutedController.text);
                            mutedController.clear();
                          },
                        ),
                      ),
                      onSubmitted: (v) {
                        app.addMutedWord(v);
                        mutedController.clear();
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final w in app.mutedWords)
                          InputChip(
                            label: Text(w),
                            onDeleted: () => app.removeMutedWord(w),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _header('Darstellung'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Hell')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dunkel')),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.setThemeMode(s.first),
                ),
              ),
              _header('Quellenliste'),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Quellenliste aktualisieren'),
                subtitle: Text('Version ${app.catalog.version} · '
                    '${app.catalog.sources.length} Quellen'),
                onTap: () async => _snack(await app.syncCatalog()),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Dialog zum Hinzufügen oder Bearbeiten eines eigenen Feeds.
class _FeedDialog extends StatefulWidget {
  final CustomFeed? existing;
  const _FeedDialog({this.existing});

  @override
  State<_FeedDialog> createState() => _FeedDialogState();
}

class _FeedDialogState extends State<_FeedDialog> {
  final app = AppState.instance;
  late final urlController =
      TextEditingController(text: widget.existing?.url ?? '');
  late final titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late String category = widget.existing?.category ?? 'top';
  late bool unfiltered = widget.existing?.unfiltered ?? false;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    urlController.dispose();
    titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    final existing = widget.existing;
    String? result;
    if (existing == null) {
      result = await app.addCustomFeed(
        url: urlController.text,
        title: titleController.text,
        category: category,
        unfiltered: unfiltered,
      );
    } else {
      await app.updateCustomFeed(existing,
          title: titleController.text,
          category: category,
          unfiltered: unfiltered);
    }
    if (!mounted) return;
    if (result == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? 'Feed hinzufügen' : 'Feed bearbeiten'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              enabled: isNew,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Feed-Adresse (RSS oder Atom)',
                border: const OutlineInputBorder(),
                errorText: error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            CategoryDropdown(
              value: category,
              onChanged: (v) => setState(() => category = v),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Alle Beiträge ungefiltert anzeigen'),
              subtitle: const Text('Schaltet den Paywall-Filter für diesen '
                  'Feed aus.'),
              value: unfiltered,
              onChanged: (v) => setState(() => unfiltered = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Prüfe …' : 'Speichern'),
        ),
      ],
    );
  }
}
