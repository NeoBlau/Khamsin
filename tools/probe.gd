extends Node
## Разовые замеры. Не тест — инструмент: печатает числа, по которым настраиваются
## параметры генерации. Содержимое меняется под текущий вопрос.


func _ready() -> void:
	Rng.set_world_seed(20260907)
	var build_start := Time.get_ticks_msec()
	World.build_now(20260907)
	print("сборка мира: %d мс" % (Time.get_ticks_msec() - build_start))

	var field := World.field
	var start := Time.get_ticks_msec()
	var sum := 0.0
	for i: int in 100000:
		sum += field.height(float(i) * 0.37, float(i) * 0.11)
	var elapsed := Time.get_ticks_msec() - start
	print("height(): %d мс на 100k вызовов → %.1f тыс/с" % [elapsed, 100000.0 / maxf(float(elapsed), 1.0)])

	start = Time.get_ticks_msec()
	sum += field.base_height(1.0, 2.0)
	for i: int in 100000:
		sum += field.base_height(float(i) * 0.37, float(i) * 0.11)
	print("base_height(): %d мс на 100k" % (Time.get_ticks_msec() - start))

	for divisions: int in [8, 32, 64, 128]:
		start = Time.get_ticks_msec()
		TerrainChunk.build_data(field, Vector2(512.0, 512.0), 256.0, divisions, 2.0, false, false, 1)
		print("чанк LOD div=%d: %d мс" % [divisions, Time.get_ticks_msec() - start])

	start = Time.get_ticks_msec()
	TerrainChunk.build_data(field, Vector2(512.0, 512.0), 256.0, 128, 2.0, true, true, 1)
	print("чанк div=128 + коллизия + камни: %d мс" % (Time.get_ticks_msec() - start))
	print("контрольная сумма: %.1f" % sum)
	get_tree().quit()
