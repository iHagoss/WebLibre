// Supported pane counts for the multi-pane browser layout.
//
// This enum is intentionally UI-framework-light: it defines only the data
// needed to drive layout decisions and pane mode controls. Native attachment
// is handled separately via the pane controller and the pane-aware
// GeckoView/platform-view path.
enum PaneMode {
  single,
  two,
  three,
  four;

  /// Number of visible panes for this mode.
  int get paneCount => switch (this) {
    PaneMode.single => 1,
    PaneMode.two => 2,
    PaneMode.three => 3,
    PaneMode.four => 4,
  };

  /// Short display label suitable for compact 1/2/3/4 mode buttons on a phone.
  String get displayLabel => switch (this) {
    PaneMode.single => '1',
    PaneMode.two => '2',
    PaneMode.three => '3',
    PaneMode.four => '4',
  };

  /// Long-form accessibility / semantic label.
  String get semanticLabel => switch (this) {
    PaneMode.single => 'Single pane',
    PaneMode.two => 'Two panes',
    PaneMode.three => 'Three panes',
    PaneMode.four => 'Four panes',
  };

  /// Returns the next pane mode in 1 -> 2 -> 3 -> 4 -> 1 order.
  PaneMode get next {
    const values = PaneMode.values;
    final nextIndex = (index + 1) % values.length;
    return values[nextIndex];
  }

  /// Returns the previous pane mode in 1 -> 4 -> 3 -> 2 -> 1 order.
  PaneMode get previous {
    const values = PaneMode.values;
    final prevIndex = (index - 1 + values.length) % values.length;
    return values[prevIndex];
  }

  /// Resolve a pane mode from a paneCount value. Defaults to [PaneMode.single]
  /// for unsupported counts so callers always get a valid mode.
  static PaneMode fromPaneCount(int count) => switch (count) {
    1 => PaneMode.single,
    2 => PaneMode.two,
    3 => PaneMode.three,
    4 => PaneMode.four,
    _ => PaneMode.single,
  };
}
