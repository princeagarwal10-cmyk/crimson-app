# Crimson Flutter Version 1.0

Flutter rebuild of Crimson Catalogue Studio.

This project is intentionally separate from the working Python desktop app.
The Python app remains the daily-use catalogue master until this Flutter version reaches feature parity.

## Goal

Build a modern Flutter desktop catalogue master using the same rules as the Python app:

- Product master
- Category and subcategory control
- Product images
- Size/finish variation matrix
- Excel/paste import rules
- Search and filters
- Catalogue PDF/share-image templates
- Future Supabase sync

## Current Status

- Version 1.0.22 is available for Windows and Android.
- Desktop and Android use the same local-first catalogue and Supabase live workspace.
- Products, variations, multiple images, categories, subcategories, brands,
  bulk paste, Excel tools, premium exports, backups, and cloud refresh are live.
- Categories, subcategories, and brands support editable names and cover images.
- The catalogue manager detects likely singular/plural duplicates and merges them
  while preserving linked products, photos, variation order, and prices.

## Non-Negotiable Rule

Do not invent new catalogue rules in Flutter.
Every rule must match the Python app unless the rulebook is intentionally updated.
