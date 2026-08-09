String normalizeContractSymbol(String symbol) => symbol.trim().toUpperCase();

String baseAssetFromSymbol(String symbol) => normalizeContractSymbol(
  symbol,
).replaceFirst(RegExp(r'(USDT|USDC|USD)$'), '');
