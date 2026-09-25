extends Node
## Снимок любого экрана интерфейса. Отдельно от screenshot.gd, потому что тому
## нужен собранный мир, а экранам — только тема и шрифты.
##
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1600x900 \
##     res://tools/ui_shot.tscn -- --scene res://scenes/ui/cover.tscn --out /tmp/a.png


func _ready() -> void:
	var path := _argument("--scene", "res://scenes/ui/cover.tscn")
	var out := _argument("--out", "user://ui.png")
	var warmup := int(_argument("--warmup", "12"))
	var hold := float(_argument("--hold", "0.0"))

	var scene: PackedScene = load(path)
	if scene == null:
		push_error("Не загрузился экран: %s" % path)
		get_tree().quit(1)
		return
	var instance := scene.instantiate()
	add_child(instance)
	print("экран: %s" % path)

	if hold > 0.0:
		var began := Time.get_ticks_msec()
		while float(Time.get_ticks_msec() - began) / 1000.0 < hold:
			await get_tree().process_frame
	for _i: int in warmup:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	if image.save_png(out) != OK:
		push_error("Снимок не сохранён")
	else:
		print("Снимок: %s (%dx%d)" % [out, image.get_width(), image.get_height()])
	get_tree().quit()


func _argument(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback
