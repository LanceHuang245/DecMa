import 'dart:math';

/// Creates a non-secret placeholder for a key stored in secure storage.
String? createSecretMask(bool hasSavedKey) {
  if (!hasSavedKey) return null;
  const characters = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(
    24,
    (_) => characters[random.nextInt(characters.length)],
  ).join();
}
