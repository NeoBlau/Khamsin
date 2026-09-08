extends Node
## Точка входа. Ничего не делает сама: прогревает справочники и уходит в меню.
##
## Отдельная сцена нужна, чтобы автолоады успели инициализироваться до того, как
## что-то попросит у них данные, и чтобы холодный старт не упирался в загрузку
## мира.


func _ready() -> void:
	Catalog.ensure_loaded()
	var missing := _validate_data()
	if not missing.is_empty():
		push_error("Boot: не хватает данных — %s" % ", ".join(missing))
	# Один кадр, чтобы окно успело появиться до смены сцены.
	await get_tree().process_frame
	get_tree().change_scene_to_file(SceneRouter.MENU_SCENE)


func _validate_data() -> PackedStringArray:
	var missing := PackedStringArray()
	if Catalog.all_vehicles().is_empty():
		missing.append("машины")
	if Catalog.all_cargo().is_empty():
		missing.append("грузы")
	return missing
