enum StockAvailability { notRecorded, inStock, lowStock, outOfStock }

StockAvailability stockAvailabilityFor(double? availablePieces) {
  if (availablePieces == null || !availablePieces.isFinite) {
    return StockAvailability.notRecorded;
  }
  if (availablePieces >= 50) return StockAvailability.inStock;
  if (availablePieces > 0) return StockAvailability.lowStock;
  return StockAvailability.outOfStock;
}
