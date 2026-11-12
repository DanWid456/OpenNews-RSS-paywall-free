import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../l10n.dart';
import '../models.dart';
import 'pickers.dart';

/// Hinweis auf Pro mit Kaufmöglichkeit.
Future<void> showProDialog(BuildContext context) async {
  final app = AppState.instance;
  final messenger = ScaffoldMessenger.of(context);
  final price = app.pro.priceLabel;
  final body = tr('pro_dialog', {'m': kFreeCustomFeeds}) +
      (price.isEmpty ? '' : '\n\n${tr('price', {'p': price})}');
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(tr('pro_unlock')),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(dialog);
            await app.pro.restore();
            messenger
                .showSnackBar(SnackBar(content: Text(tr('pro_restoring'))));
          },
          child: Text(tr('pro_restore')),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(dialog);
            final started = await app.pro.buy();
            if (!started) {
              messenger
                  .showSnackBar(SnackBar(content: Text(tr('buy_failed'))));
            }
          },
          child: Text(tr('buy')),
        ),
      ],
    ),
  );
}

/// Öffnet den Dialog für einen neuen eigenen Feed – oder den Pro-Hinweis,
/// wenn die Freigrenze erreicht ist.
Future<void> showAddFeed(BuildContext context) async {
  if (!AppState.instance.canAddFeed) {
    await showProDialog(context);
    return;
  }
  await showDialog<void>(
      context: context, builder: (_) => const AddFeedDialog());
}

/// Neuer eigener Feed: Adresse eingeben oder per Stichwort suchen.
class AddFeedDialog extends StatefulWidget {
  const AddFeedDialog({super.key});

  @override
  State<AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<AddFeedDialog> {
  final app = AppState.instance;
  final queryController = TextEditingController();
  final titleController = TextEditingController();
  String category = 'top';
  bool unfiltered = false;
  bool saving = false;
  bool searching = false;
  String? error;
  List<FeedSuggestion>? suggestions;

  @override
  void dispose() {
    queryController.dispose();
    titleController.dispose();
    super.dispose();
  }

  bool get _isAddress {
    final q = queryController.text.trim();
    return q.startsWith('http') || q.contains('.');
  }

  Future<void> _search() async {
    setState(() {
      searching = true;
      error = null;
      suggestions = null;
    });
    final found = await app.suggestFeeds(queryController.text);
    if (!mounted) return;
    setState(() {
      searching = false;
      suggestions = found;
    });
  }

  void _pick(FeedSuggestion s) {
    setState(() {
      queryController.text = s.url;
      if (titleController.text.trim().isEmpty) titleController.text = s.title;
      suggestions = null;
    });
  }

  Future<void> _save() async {
    if (!_isAddress) {
      // Ein Stichwort ist noch keine Adresse – erst Vorschläge suchen.
      await _search();
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final result = await app.addCustomFeed(
      url: queryController.text,
      title: titleController.text,
      category: category,
      unfiltered: unfiltered,
    );
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
    final found = suggestions;
    final busy = saving || searching;
    return AlertDialog(
      title: Text(tr('add_feed')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: queryController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: tr('feed_query'),
                hintText: tr('feed_query_hint'),
                border: const OutlineInputBorder(),
                errorText: error,
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: tr('find'),
                  icon: const Icon(Icons.search),
                  onPressed: busy ? null : _search,
                ),
              ),
            ),
            if (searching)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(tr('searching')),
                  ],
                ),
              ),
            if (found != null && found.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(tr('no_suggestions')),
              ),
            if (found != null)
              for (final s in found)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.rss_feed),
                  title: Text(s.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(s.url,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _pick(s),
                ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: tr('name_optional'),
                border: const OutlineInputBorder(),
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
              title: Text(tr('unfiltered_check')),
              subtitle: Text(tr('unfiltered_sub')),
              value: unfiltered,
              onChanged: (v) => setState(() => unfiltered = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(tr('cancel')),
        ),
        FilledButton(
          onPressed: busy ? null : _save,
          child: Text(saving ? tr('checking') : tr('save')),
        ),
      ],
    );
  }
}

/// Name und Thema eines Feeds anpassen. Bei eigenen Feeds zusätzlich
/// «ungefiltert» und Entfernen.
class EditFeedDialog extends StatefulWidget {
  final FeedEntry entry;
  const EditFeedDialog({super.key, required this.entry});

  @override
  State<EditFeedDialog> createState() => _EditFeedDialogState();
}

class _EditFeedDialogState extends State<EditFeedDialog> {
  final app = AppState.instance;
  late final CustomFeed? custom = widget.entry.isCustom
      ? app.customFeedByUrl(widget.entry.url)
      : null;
  late final nameController =
      TextEditingController(text: widget.entry.listName);
  late String category = widget.entry.categories.isEmpty
      ? 'top'
      : widget.entry.categories.first;
  late bool unfiltered = custom?.unfiltered ?? false;

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = custom;
    if (c != null) {
      await app.updateCustomFeed(c,
          title: nameController.text,
          category: category,
          unfiltered: unfiltered);
    } else {
      // Unveränderter Vorgabename wird nicht als eigener Name gespeichert,
      // sonst stünde z. B. «SRF – Wirtschaft» statt «SRF» in der Artikelliste.
      final e = widget.entry;
      final typed = nameController.text.trim();
      final untouched = typed == e.listName && e.label == e.source.name;
      await app.setFeedOverride(e.url,
          name: untouched ? '' : typed, category: category);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = custom;
    return AlertDialog(
      title: Text(tr('edit_feed')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: tr('name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            CategoryDropdown(
              value: category,
              onChanged: (v) => setState(() => category = v),
            ),
            if (c != null) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(tr('unfiltered_check')),
                subtitle: Text(tr('unfiltered_sub')),
                value: unfiltered,
                onChanged: (v) => setState(() => unfiltered = v ?? false),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (c != null)
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await app.removeCustomFeed(c);
            },
            child: Text(tr('delete_feed')),
          )
        else
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await app.resetFeedOverride(widget.entry.url);
            },
            child: Text(tr('reset')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('save'))),
      ],
    );
  }
}
