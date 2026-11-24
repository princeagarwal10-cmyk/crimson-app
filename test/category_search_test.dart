import 'package:crimson_catalogue_studio/core/rules/catalogue_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category search matches words as they are typed', () {
    expect(categoryNameMatchesSearch('MORTISE LOCKS', 'mor'), isTrue);
    expect(categoryNameMatchesSearch('MORTISE LOCKS', 'mortise'), isTrue);
    expect(categoryNameMatchesSearch('MORTISE LOCKS', 'locks'), isTrue);
    expect(categoryNameMatchesSearch('MORTISE LOCKS', 'mor loc'), isTrue);
    expect(categoryNameMatchesSearch('MORTISE LOCKS', 'cabinet'), isFalse);
    expect(categoryNameMatchesSearch('MORTISE LOCKS', ''), isFalse);
  });
}
