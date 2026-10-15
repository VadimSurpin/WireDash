import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/pro/pro.dart';

void main() {
  // Tests build without ZIGDASH_FLAVOR, which is the foss build.
  test('the foss build has everything unlocked and nothing to buy', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(proFlavor, 'foss');
    expect(c.read(proStatusProvider), ProStatus.unlocked);
    expect(c.read(proPurchaseProvider), isNull);
  });
}
