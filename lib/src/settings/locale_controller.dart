import 'package:cairn/src/settings/locale_store.dart';
import 'package:flutter/widgets.dart';

/// App-wide reactive holder for the chosen UI locale.
///
/// `null` means "follow the device locale". Every change is persisted through
/// the [LocaleStore], so the choice survives a restart. The root `MaterialApp`
/// listens to this and relocalises the whole app when it changes.
class LocaleController extends ValueNotifier<Locale?> {
  /// Creates a controller seeded with [initial], persisting through a
  /// [LocaleStore].
  new(this._store, {required Locale? initial}) : super(initial);

  final LocaleStore _store;

  /// Sets the active [locale] (`null` = follow the system) and persists it.
  Future<void> setLocale(Locale? locale) async {
    value = locale;
    await _store.write(locale?.languageCode);
  }
}
