import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../config.dart';
import '../l10n.dart';
import '../widgets/feed_dialogs.dart';
import '../widgets/pickers.dart';
import '../widgets/tiles.dart' show kReadGreen;

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

  // --- Import / Export ---

  Future<void> _runImport(String text) async {
    if (text.trim().isEmpty) return;
    _snack(tr('import_checking'));
    final added = await app.importFeeds(text);
    var message = tr('import_done', {'n': added});
    if (!app.canAddFeed) message = '$message ${tr('import_limit')}';
    _snack(message);
  }

  Future<void> _importFromFile() async {
    try {
      final file = await openFile();
      if (file == null) return;
      await _runImport(await file.readAsString());
    } catch (_) {
      _snack(tr('import_file_err'));
    }
  }

  Future<void> _importFeeds() async {
    if (!app.canAddFeed) {
      await showProDialog(context);
      return;
    }
    final controller = TextEditingController();
    // Ergebnis: eingefügter Text, '' für «Datei wählen», null für Abbruch.
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(tr('import_opml')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialog, ''),
                icon: const Icon(Icons.folder_open),
                label: Text(tr('import_file')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: tr('import_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) Navigator.pop(dialog, text);
              },
              child: Text(tr('import_btn'))),
        ],
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      await _importFromFile();
    } else {
      await _runImport(result);
    }
  }

  Future<void> _exportFeeds() async {
    await Clipboard.setData(ClipboardData(text: app.exportOpml()));
    _snack(tr('export_done'));
  }

  // --- Pro ---

  Widget _proSection() {
    final theme = Theme.of(context);
    if (app.isPro) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          children: [
            const Icon(Icons.check_circle, size: 56, color: kReadGreen),
            const SizedBox(height: 8),
            Text(kAppName,
                style: theme.textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(tr('pro_active'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    final price = app.pro.priceLabel;
    return ListTile(
      leading: const Icon(Icons.workspace_premium_outlined),
      title: Text(tr('pro_unlock')),
      subtitle: Text(
          price.isEmpty ? tr('pro_sub') : tr('pro_sub_price', {'p': price})),
      onTap: () => showProDialog(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final interests = app.interests.toSet();
        final custom = app.entries.where((e) => e.isCustom).toList();
        return Scaffold(
          appBar: AppBar(title: Text(tr('nav_settings'))),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SectionHeader(tr('sec_region')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RegionPicker(
                  country: app.country,
                  language: app.language,
                  onChanged: app.setRegion,
                ),
              ),
              SectionHeader(tr('sec_interests')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InterestChips(
                  selected: interests,
                  onChanged: (s) {
                    if (s.isEmpty) return;
                    app.setInterests(
                        kCategoryIds.where(s.contains).toList());
                  },
                ),
              ),
              SectionHeader(tr('sec_pro')),
              _proSection(),
              SectionHeader(tr('sec_custom')),
              if (!app.isPro)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    tr('custom_free', {
                      'n': app.customFeeds.length > kFreeCustomFeeds
                          ? kFreeCustomFeeds
                          : app.customFeeds.length,
                      'm': kFreeCustomFeeds,
                    }),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              for (final e in custom)
                ListTile(
                  title: Text(e.listName),
                  subtitle: Text([
                    if (e.categories.isNotEmpty)
                      tr('cat_${e.categories.first}'),
                    e.source.unfiltered ? tr('filter_off') : tr('filter_on'),
                  ].join(' · ')),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => EditFeedDialog(entry: e)),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(tr('add_feed')),
                onTap: () => showAddFeed(context),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: Text(tr('import_opml')),
                onTap: _importFeeds,
              ),
              if (custom.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: Text(tr('export_opml')),
                  onTap: _exportFeeds,
                ),
              SectionHeader(tr('sec_filter')),
              SwitchListTile(
                title: Text(tr('deep')),
                subtitle: Text(tr('deep_sub')),
                value: app.deepCheck,
                onChanged: app.setDeepCheck,
              ),
              SectionHeader(tr('sec_muted')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: mutedController,
                      decoration: InputDecoration(
                        hintText: tr('muted_hint'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          tooltip: tr('add'),
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
              SectionHeader(tr('sec_display')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabeledDropdown(
                      label: tr('app_language'),
                      value: app.uiLanguage,
                      options: {
                        'system': tr('lang_system'),
                        for (final code in kUiLanguages)
                          code: kLanguages[code] ?? code,
                      },
                      onChanged: app.setUiLanguageChoice,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                            value: ThemeMode.system,
                            label: Text(tr('theme_system'))),
                        ButtonSegment(
                            value: ThemeMode.light,
                            label: Text(tr('theme_light'))),
                        ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text(tr('theme_dark'))),
                      ],
                      selected: {app.themeMode},
                      onSelectionChanged: (s) => app.setThemeMode(s.first),
                    ),
                  ],
                ),
              ),
              SectionHeader(tr('sec_catalog')),
              ListTile(
                leading: const Icon(Icons.sync),
                title: Text(tr('catalog_update')),
                subtitle: Text(tr('catalog_info', {
                  'v': app.catalog.version,
                  'n': app.catalog.sources.length,
                })),
                onTap: () async => _snack(await app.syncCatalog()),
              ),
            ],
          ),
        );
      },
    );
  }
}
