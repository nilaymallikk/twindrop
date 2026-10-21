import 'package:flutter_test/flutter_test.dart';
import 'package:twindrop/desktop/shell_args.dart';

void main() {
  test('parses each launch flag', () {
    final args = ShellArgs.parse(['--hidden', '--quick-send']);
    expect(args.hidden, isTrue);
    expect(args.quickSend, isTrue);
    expect(args.open, isFalse);
    expect(args.quit, isFalse);
    expect(args.forwardFlag, '--quick-send');
  });

  test('ignores unknown flags and prefers the longest command', () {
    final args = ShellArgs.parse(['--open', '--quit', '--unknown']);
    expect(args.quit, isTrue);
    expect(args.open, isTrue);
    expect(args.forwardFlag, '--quit');
  });

  test('no flags stays empty', () {
    final args = ShellArgs.parse(const []);
    expect(args.hidden || args.quickSend || args.open || args.quit, isFalse);
    expect(args.forwardFlag, isNull);
  });
}
