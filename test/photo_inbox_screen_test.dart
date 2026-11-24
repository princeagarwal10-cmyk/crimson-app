import 'dart:io';

import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/features/catalogue/presentation/photo_inbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late File firstPhoto;
  late File secondPhoto;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('crimson-photo-test-');
    firstPhoto = await File('${temp.path}/one.jpg').writeAsBytes([1, 2, 3]);
    secondPhoto = await File('${temp.path}/two.jpg').writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } on FileSystemException {
      // Windows can retain an image decoder handle until the test process exits.
    }
  });

  testWidgets('upload stays disabled until private cloud storage is ready',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PhotoInboxScreen(
        state: const CatalogueState(),
        onSaveState: (_) async {},
        onResolveImage: (path) async => File(path),
        onCheckCloudReady: () async => false,
      ),
    ));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Upload Photos'))
            .onPressed,
        isNull);
    expect(find.textContaining('private cloud setup'), findsOneWidget);
  });

  testWidgets('selected images form one draft without deleting their paths',
      (tester) async {
    var state = CatalogueState(photoInbox: [
      PhotoInboxDraft(
          id: 'photo-one', images: [PhotoInboxImage(path: firstPhoto.path)]),
      PhotoInboxDraft(
          id: 'photo-two', images: [PhotoInboxImage(path: secondPhoto.path)]),
    ]);
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
      builder: (context, refresh) => PhotoInboxScreen(
        state: state,
        onSaveState: (next) async => refresh(() => state = next),
        onResolveImage: (path) async => File(path),
      ),
    )));

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Group Selected'))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('Group Selected'));
    await tester.pumpAndSettle();

    final active = state.photoInbox.where((draft) => draft.isActive).toList();
    expect(active, hasLength(1));
    expect(active.single.images.map((image) => image.path),
        [firstPhoto.path, secondPhoto.path]);
    expect(state.photoInbox, hasLength(2));
  });

  testWidgets('a grouped draft becomes one coming soon product',
      (tester) async {
    var state = CatalogueState(
      photoInbox: [
        PhotoInboxDraft(
          id: 'photo-group',
          name: 'W Emmy',
          category: 'Cabinet Handles',
          subcategory: 'Welset',
          images: [
            PhotoInboxImage(path: firstPhoto.path, finish: 'Matt Black'),
            PhotoInboxImage(path: secondPhoto.path, finish: 'Rose Gold'),
          ],
        )
      ],
      categories: const [
        CategoryDraft(
          name: 'Cabinet Handles',
          subcategories: ['Welset'],
          isPublished: true,
          subcategoryPublished: {'Welset': true},
        )
      ],
    );
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
      builder: (context, refresh) => PhotoInboxScreen(
        state: state,
        onSaveState: (next) async {
          refresh(() => state = next);
        },
        onResolveImage: (path) async => File(path),
      ),
    )));

    final comingSoonButton = find.widgetWithText(TextButton, 'Coming Soon');
    expect(tester.widget<TextButton>(comingSoonButton).onPressed, isNotNull);
    await tester.runAsync(() async {
      tester.widget<TextButton>(comingSoonButton).onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not show product yet'), findsNothing);

    expect(state.products, hasLength(1));
    expect(state.products.single.isComingSoon, isTrue);
    expect(state.products.single.isPublished, isFalse);
    expect(
        state.products.single.imagePaths, [firstPhoto.path, secondPhoto.path]);
    expect(
        state.products.single.imageFinishTags[secondPhoto.path], 'Rose Gold');
    expect(state.photoInbox.single.isConverted, isTrue);
  });
}
