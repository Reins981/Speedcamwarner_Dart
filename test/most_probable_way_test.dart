import 'package:test/test.dart';
import 'package:workspace/most_probable_way.dart';

void main() {
  test('roadname list resets when max reached', () {
    final mpw = MostProbableWay();
    mpw.setMaximumNumberOfRoadNames(2);
    mpw.addRoadnameToRoadnameList('A');
    mpw.addRoadnameToRoadnameList('B');
    mpw.addRoadnameToRoadnameList('C');
    expect(mpw.lastRoadnameList, ['C']);
  });

  test('detects consistent next possible MPR', () {
    final mpw = MostProbableWay();
    mpw.setMaximumNumberOfNextPossibleMprs(3);
    mpw.addAttributesToNextPossibleMprList(1, 'Main');
    mpw.addAttributesToNextPossibleMprList(1, 'Main');
    mpw.addAttributesToNextPossibleMprList(1, 'Main');
    final result = mpw.isNextPossibleMprNewMpr(
        currentFr: 1,
        mostProbableRoadClass: 1,
        ramp: false,
        nextMprListComplete: true);
    expect(result, isTrue);
  });
}
