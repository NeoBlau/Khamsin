#!/usr/bin/env bash
# Прогон тестов. Импорт перед запуском обязателен: без него Godot не видит
# новые class_name, и всё, что на них ссылается, «не компилируется».
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"

"$GODOT" --headless --path "$HERE" --import >/dev/null 2>&1

"$GODOT" --headless --path "$HERE" res://tests/run_tests.tscn -- "$@" 2>&1 \
  | grep -vE "^(Godot Engine v|https://godotengine)" \
  | grep -vE "^(WARNING: ObjectDB|ERROR: Pages in use|   at: (cleanup|~PagedAllocator))"
exit "${PIPESTATUS[0]}"
