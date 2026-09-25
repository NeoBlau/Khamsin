#!/usr/bin/env bash
# Запуск игры.
#
#   tools/run.sh                # обычный запуск
#   tools/run.sh --editor       # открыть в редакторе
#   tools/run.sh --reimport     # переимпортировать принудительно
#   GODOT=/path/to/godot tools/run.sh
#
# Скрипт существует ради одной строчки — импорта, и решает он одну проблему,
# но в двух её видах.
#
# Первый: свежий клон. Каталога .godot нет, значит нет и кеша глобальных
# классов. Типы, объявленные через class_name, движку неизвестны, автолоады не
# компилируются, и игра уходит в поток ошибок вида «Could not find type X».
# Плоский «godot --path .» это не чинит и не починит никогда: кеш появляется
# только после импорта.
#
# Второй, и он встречается чаще: git pull. Каталог .godot на месте, кеш тоже,
# но он старый — новых class_name в нём не значится. Симптом ровно тот же, а
# проверка «есть ли каталог» его пропускает. Поэтому сравниваем время: если
# хоть один исходник новее кеша, импорт нужен.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
CACHE="$HERE/.godot/global_script_class_cache.cfg"

FORCE=0
ARGS=()
for arg in "$@"; do
  if [ "$arg" = "--reimport" ]; then
    FORCE=1
  else
    ARGS+=("$arg")
  fi
done

needs_import() {
  [ "$FORCE" = "1" ] && return 0
  [ -f "$CACHE" ] || return 0
  # Любой исходник или ресурс новее кеша — повод переимпортировать.
  # find -newer сравнивает время изменения, а git pull его как раз обновляет.
  local newer
  newer="$(find "$HERE/src" "$HERE/scenes" "$HERE/shaders" "$HERE/data" \
    "$HERE/tools" "$HERE/tests" "$HERE/project.godot" \
    -newer "$CACHE" -print -quit 2>/dev/null || true)"
  [ -n "$newer" ]
}

if needs_import; then
  if [ -f "$CACHE" ]; then
    echo "Исходники новее кеша импорта — переимпортирую…"
  else
    echo "Первый запуск: импортирую ресурсы, это одна-две минуты…"
  fi
  "$GODOT" --headless --path "$HERE" --import >/dev/null
fi

exec "$GODOT" --path "$HERE" ${ARGS[@]+"${ARGS[@]}"}
