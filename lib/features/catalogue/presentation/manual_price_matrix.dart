import '../../../core/rules/catalogue_rules.dart';
import '../domain/catalogue_models.dart';

List<VariationDraft> buildManualPriceMatrixVariations({
  required List<String> finishes,
  required List<String> sizes,
  required String Function(String finish, String size) priceFor,
  List<VariationDraft> existingVariations = const [],
}) {
  final variations = <VariationDraft>[];
  for (final finish in finishes) {
    for (final size in sizes) {
      final rawPrice = cleanText(priceFor(finish, size));
      if (rawPrice.isEmpty || rawPrice == '-') continue;

      final parsedPrice = parsePrice(rawPrice);
      final amount = double.parse(parsedPrice);
      final match = existingVariations.where((item) =>
          _sameMatrixLabel(item.finish, finish) &&
          _sameMatrixLabel(item.size, size));
      final existing = match.isEmpty ? null : match.first;
      // Imported rows can have a zero price. Keep them on an unchanged save;
      // a newly blanked cell, or a positive price changed to zero, is removed.
      if (amount <= 0 &&
          (existing == null || double.tryParse(existing.price) != 0)) {
        continue;
      }

      final dimensions = parseBreadthLengthHeight(size);
      variations.add(
        VariationDraft(
          finish: existing?.finish ?? finish,
          size: existing?.size ?? size,
          breadth: existing?.breadth ?? dimensions.breadth,
          length: existing?.length ?? dimensions.length,
          height: existing?.height ?? dimensions.height,
          thickness: existing?.thickness ?? '',
          price: parsedPrice,
          sku: existing?.sku ?? '',
          notes: existing?.notes ?? '',
        ),
      );
    }
  }
  return variations;
}

bool _sameMatrixLabel(String left, String right) =>
    cleanText(left).toLowerCase() == cleanText(right).toLowerCase();
