/// A ready-made view of the Orders tab that a dashboard tile opens. The
/// meanings mirror the dashboard's own counts so the list ends up with the
/// same number of rows the tile promised.
enum OrdersDrillDown {
  /// Every order not yet delivered, whatever its date ("Open orders").
  open,

  /// Delivered today ("Delivered").
  deliveredToday,

  /// Not delivered and due today ("Due today").
  dueToday,

  /// Not delivered and due before today ("Overdue").
  overdue,
}
