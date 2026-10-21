/// Command-line flags understood by the desktop entry point.
class ShellArgs {
  const ShellArgs({
    this.hidden = false,
    this.quickSend = false,
    this.open = false,
    this.quit = false,
  });

  /// Start with no window; the tray owns the session.
  final bool hidden;

  /// Show the popup and send the current clipboard text.
  final bool quickSend;

  /// Show the main window (also used to raise an already running instance).
  final bool open;

  /// Stop the running instance.
  final bool quit;

  static ShellArgs parse(List<String> args) {
    return ShellArgs(
      hidden: args.contains('--hidden'),
      quickSend: args.contains('--quick-send'),
      open: args.contains('--open'),
      quit: args.contains('--quit'),
    );
  }

  /// The flag a second launch should forward to the running instance, if any.
  /// Longer commands win so `--quit` is never mistaken for a display request.
  String? get forwardFlag {
    if (quit) return '--quit';
    if (quickSend) return '--quick-send';
    if (open) return '--open';
    if (hidden) return '--hidden';
    return null;
  }
}
