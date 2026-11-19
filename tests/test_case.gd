class_name TestCase
extends RefCounted
## Base for engine-free unit tests. Name methods test_*; the runner calls each on a fresh instance.

var failures: PackedStringArray = []
## How many assert_* calls ran. The runner fails a test that ran none: it proved nothing.
var checks: int = 0


func assert_true(cond: bool, msg: String = "") -> void:
	checks += 1
	if not cond:
		failures.append("expected true %s" % msg)


func assert_false(cond: bool, msg: String = "") -> void:
	checks += 1
	if cond:
		failures.append("expected false %s" % msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	checks += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("expected %s, got %s %s" % [var_to_str(expected), var_to_str(actual), msg])


func assert_near(actual: float, expected: float, eps: float = 0.0001, msg: String = "") -> void:
	checks += 1
	if absf(actual - expected) > eps:
		failures.append("expected %f +- %f, got %f %s" % [expected, eps, actual, msg])
