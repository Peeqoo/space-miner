class_name NumberFormat


static func format_compact(value: int) -> String:
	var abs_value: int = absi(value)
	var sign: String = "-" if value < 0 else ""

	if abs_value < 1000:
		return str(value)

	var suffixes: Array[String] = ["K", "M", "B", "T"]
	var divisors: Array[int] = [1_000, 1_000_000, 1_000_000_000, 1_000_000_000_000]

	var selected_index: int = 0
	for i: int in range(divisors.size()):
		if abs_value >= divisors[i]:
			selected_index = i

	var scaled: float = float(abs_value) / float(divisors[selected_index])
	var suffix: String = suffixes[selected_index]

	if scaled >= 100.0:
		return "%s%d%s" % [sign, int(floor(scaled)), suffix]

	if scaled >= 10.0:
		return "%s%.1f%s" % [sign, scaled, suffix]

	return "%s%.2f%s" % [sign, scaled, suffix]


static func format_compact_float(value: float) -> String:
	return format_compact(int(round(value)))
