/// turbotoken Flutter example — demonstrates basic token encoding/decoding.
import 'package:turbotoken/turbotoken.dart';

Future<void> main() async {
  // List available encodings.
  print('Available encodings: ${TurboToken.listEncodingNames().join(', ')}');

  // Get the encoding used by GPT-4o.
  final enc = await TurboToken.getEncodingForModel('gpt-4o');
  print('Encoding for gpt-4o: ${enc.name}');

  // Encode text to tokens.
  const text = 'Hello, world! This is turbotoken.';
  final tokens = enc.encode(text);
  print('Text: "$text"');
  print('Tokens (${tokens.length}): $tokens');

  // Decode tokens back to text.
  final decoded = enc.decode(tokens);
  print('Decoded: "$decoded"');
  assert(decoded == text, 'Round-trip mismatch!');

  // Count tokens without allocating the token array.
  final count = enc.count(text);
  print('Token count: $count');

  // Check token limit.
  final withinLimit = enc.isWithinTokenLimit(text, 100);
  print('Within 100-token limit: ${withinLimit != null ? "yes ($withinLimit tokens)" : "no"}');

  // Chat message encoding.
  final chatTokens = enc.encodeChat([
    const ChatMessage(role: 'system', content: 'You are a helpful assistant.'),
    const ChatMessage(role: 'user', content: 'What is BPE tokenization?'),
  ]);
  print('Chat tokens: ${chatTokens.length}');

  // Version.
  try {
    print('Native library version: ${TurboToken.version()}');
  } catch (e) {
    print('Native library not available (expected in non-Flutter environments)');
  }
}
