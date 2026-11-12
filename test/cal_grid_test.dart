import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/cal_grid.dart';

void main() {
  test('a tap lands on the half hour it is in', () {
    expect(GridMath.minuteAt(0), 0);
    expect(GridMath.minuteAt(29), 0);
    expect(GridMath.minuteAt(30), 30);
    expect(GridMath.minuteAt(59.9), 30);
    expect(GridMath.minuteAt(60), 60);
    expect(GridMath.minuteAt(1439), 23 * 60 + 30);
    expect(GridMath.minuteAt(5000), 23 * 60 + 30);
    expect(GridMath.minuteAt(-20), 0);
  });

  test('the column is found from the side and kept inside the page', () {
    expect(GridMath.columnAt(0, 100, 3), 0);
    expect(GridMath.columnAt(99, 100, 3), 0);
    expect(GridMath.columnAt(100, 100, 3), 1);
    expect(GridMath.columnAt(999, 100, 3), 2);
    expect(GridMath.columnAt(-5, 100, 3), 0);
  });

  test('a dragged block snaps to quarter hours and stays in the day', () {
    expect(GridMath.movedStart(9 * 60, 0, 60), 9 * 60);
    expect(GridMath.movedStart(9 * 60, 30, 60), 9 * 60 + 30); // 30 px is half an hour
    expect(GridMath.movedStart(9 * 60, 7, 60), 9 * 60); // under a quarter of the way: stays
    expect(GridMath.movedStart(9 * 60, 8, 60), 9 * 60 + 15);
    expect(GridMath.movedStart(60, -500, 60), 0);
    expect(GridMath.movedStart(22 * 60, 500, 90), 24 * 60 - 90); // the end stays inside the day
  });

  test('a pulled bottom edge snaps to quarter hours, never under 15 minutes, never past midnight', () {
    expect(GridMath.resized(60, 0, 9 * 60), 60);
    expect(GridMath.resized(60, 30, 9 * 60), 90);
    expect(GridMath.resized(60, -200, 9 * 60), 15);
    expect(GridMath.resized(60, 5000, 23 * 60), 60); // only an hour left in the day
  });

  test('blocks that overlap share the width; ones that do not keep it all', () {
    // 9-10, 9:30-10:30, 11-12
    final l = GridMath.lanes([(540, 600), (570, 630), (660, 720)]);
    expect(l, [(0, 2), (1, 2), (0, 1)]);
  });

  test('a long block holds a lane while short ones come and go beside it', () {
    // 9-12 with 9-10 and 10-11 beside it: two lanes for all three
    final l = GridMath.lanes([(540, 720), (540, 600), (600, 660)]);
    expect(l, [(0, 2), (1, 2), (1, 2)]);
  });

  test('blocks that only touch do not overlap', () {
    expect(GridMath.lanes([(540, 600), (600, 660)]), [(0, 1), (0, 1)]);
  });
}
