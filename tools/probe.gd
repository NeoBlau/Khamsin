extends Node
## Разовые замеры по рельефу. Не тест — инструмент: печатает числа, по которым
## настраиваются амплитуды. Запуск: godot --headless res://tools/probe.tscn


func _ready() -> void:
	var field := TerrainField.new(20260907)
	field.apply_config()
	var worst_total := 0.0
	var worst_dune := 0.0
	var worst_ridge := 0.0
	var worst_detail := 0.0
	var worst_macro := 0.0
	var at := Vector2.ZERO
	var step := 6.0
	for i: int in 500:
		var x := lerpf(-6000.0, 6000.0, float(i) / 499.0)
		for j: int in 40:
			var z := lerpf(-6000.0, 6000.0, float(j) / 39.0)
			if field.dune_mask(x, z) < 0.6:
				continue
			var total := _grad(field, x, z, step, "total")
			if total > worst_total:
				worst_total = total
				at = Vector2(x, z)
			worst_dune = maxf(worst_dune, _grad(field, x, z, step, "dune"))
			worst_ridge = maxf(worst_ridge, _grad(field, x, z, step, "ridge"))
			worst_detail = maxf(worst_detail, _grad(field, x, z, step, "detail"))
			worst_macro = maxf(worst_macro, _grad(field, x, z, step, "macro"))
	print("максимальный уклон, тангенс:")
	print("  всего   %.3f в точке (%.0f, %.0f)" % [worst_total, at.x, at.y])
	print("  дюны    %.3f" % worst_dune)
	print("  гряды   %.3f" % worst_ridge)
	print("  детали  %.3f" % worst_detail)
	print("  макро   %.3f" % worst_macro)
	get_tree().quit()


func _grad(field: TerrainField, x: float, z: float, step: float, part: String) -> float:
	var dx := (_part(field, x + step, z, part) - _part(field, x - step, z, part)) / (2.0 * step)
	var dz := (_part(field, x, z + step, part) - _part(field, x, z - step, part)) / (2.0 * step)
	return Vector2(dx, dz).length()


func _part(field: TerrainField, x: float, z: float, part: String) -> float:
	match part:
		"dune":
			return field.dune_height(x, z)
		"total":
			return field.base_height(x, z)
		_:
			# Остальные слои восстанавливаем вычитанием: приватных полей не трогаем.
			return field.base_height(x, z) - field.dune_height(x, z)
