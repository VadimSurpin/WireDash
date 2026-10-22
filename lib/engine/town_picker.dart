import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/l10n/l10n_ext.dart';
import 'automations_repo.dart';

/// Towns for sunrise and sunset, bundled offline (zigdash-3.0.md §1): no
/// location permission, no lookup service. GeoNames cities over 15,000
/// people, CC BY 4.0, largest first.
const townsAsset = 'assets/geo/towns.tsv';

class TownEntry {
  const TownEntry(this.name, this.ascii, this.country, this.lat, this.lon);
  final String name;
  final String ascii;
  final String country;
  final double lat;
  final double lon;

  Town toTown() => Town(name: '$name, $country', lat: lat, lon: lon);
}

List<TownEntry> parseTowns(String tsv) => [
      for (final line in tsv.split('\n'))
        if (line.isNotEmpty && !line.startsWith('#'))
          () {
            final c = line.split('\t');
            if (c.length < 5) return null;
            final lat = double.tryParse(c[3]), lon = double.tryParse(c[4]);
            if (lat == null || lon == null) return null;
            return TownEntry(c[0], c[1], c[2], lat, lon);
          }(),
    ].whereType<TownEntry>().toList();

/// Towns whose name or plain-letter name starts with [query] first, then
/// those containing it; each group keeps the largest first.
List<TownEntry> searchTowns(List<TownEntry> towns, String query, {int limit = 30}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final starts = <TownEntry>[], contains = <TownEntry>[];
  for (final t in towns) {
    final n = t.name.toLowerCase(), a = t.ascii.toLowerCase();
    if (n.startsWith(q) || a.startsWith(q)) {
      starts.add(t);
    } else if (contains.length < limit && (n.contains(q) || a.contains(q))) {
      contains.add(t);
    }
    if (starts.length >= limit) break;
  }
  return [...starts, ...contains].take(limit).toList();
}

List<TownEntry>? _cache;

Future<List<TownEntry>> loadTowns() async {
  final cached = _cache;
  if (cached != null) return cached;
  final towns = await compute(parseTowns, await rootBundle.loadString(townsAsset));
  return _cache = towns;
}

/// Asks for a town; null when dismissed.
Future<Town?> pickTown(BuildContext context) => showModalBottomSheet<Town>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _TownSheet(),
    );

class _TownSheet extends StatefulWidget {
  const _TownSheet();

  @override
  State<_TownSheet> createState() => _TownSheetState();
}

class _TownSheetState extends State<_TownSheet> {
  List<TownEntry>? _towns;
  String _query = '';

  @override
  void initState() {
    super.initState();
    loadTowns().then((t) {
      if (mounted) setState(() => _towns = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _towns == null ? const <TownEntry>[] : searchTowns(_towns!, _query);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('town-search'),
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.autoTownSearch, helperText: l10n.autoTownWhy),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (_towns == null) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                children: [
                  for (final t in results)
                    ListTile(
                      title: Text(t.name),
                      subtitle: Text(t.country),
                      onTap: () => Navigator.of(context).pop(t.toTown()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
