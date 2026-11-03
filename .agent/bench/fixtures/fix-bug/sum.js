// Fixture for the fix-bug bench case: reduce() without an initial value throws
// on an empty array, so the fix is the initial value, not a parse fix.
export function sum(values) {
  return values.reduce((total, value) => total + value)
}
