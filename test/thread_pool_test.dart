import 'package:test/test.dart';
import '../lib/thread_pool.dart';

void main() {
  test('startThreadPoolLookup runs tasks concurrently', () async {
    final pool = ThreadPool();
    final sw = Stopwatch()..start();
    final results = await pool.startThreadPoolLookup(() => [
      Future.delayed(const Duration(milliseconds: 200), () => 1),
      Future.delayed(const Duration(milliseconds: 200), () => 2),
    ]);
    sw.stop();
    expect(results, [1, 2]);
    expect(sw.elapsedMilliseconds < 400, isTrue);
  });

  test('speedCamLookupAhead proxies to callback', () async {
    final list = await speedCamLookupAhead<int, int>(5,
        (arg) async => [arg, arg + 1]);
    expect(list, [5, 6]);
  });
}
