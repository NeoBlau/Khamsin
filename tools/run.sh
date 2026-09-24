#!/usr/bin/env bash
# Запуск игры.
#
#   tools/run.sh                # обычный запуск
#   tools/run.sh --editor       # открыть в редакторе
#   GODOT=/path/to/godot tools/run.sh
#
# Скрипт существует ради одной строчки — импорта. В свежем клоне нет каталога
# .godot, а значит нет и кеша глобальных классов: Godot не знает про типы,
# объявленные через class_name, автолоады не компилируются и игра падает в
# бесконечный поток ошибок. Плоский «godot --path .» эту ситуацию сам не
# чинит и не починит никогда — кеш появляется только после импорта.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"

if [ ! -f "$HERE/.godot/global_script_class_cache.cfg" ]; then
  echo "Первый запуск: импортирую ресурсы, это одна-две минуты…"
  "$GODOT" --headless --path "$HERE" --import >/dev/null
fi

exec "$GODOT" --path "$HERE" "$@"
