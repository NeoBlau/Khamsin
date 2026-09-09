#!/usr/bin/env bash
# Сборка игры. По умолчанию — под macOS, потому что это основная платформа.
#
#   tools/build.sh              # macOS, универсальный бинарник
#   tools/build.sh Linux        # то же для Linux
#   GODOT=/path/to/godot tools/build.sh
#
# Шаблоны экспорта Godot ставит сам при первом запуске редактора, а в консоли
# их надо положить руками — скрипт скажет куда, если их нет.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
PRESET="${1:-macOS}"
BUILD_DIR="$HERE/../../build"

VERSION="$("$GODOT" --headless --version | head -1)"
echo "Godot: $VERSION"
case "$VERSION" in
  4.5.*) ;;
  *) echo "Внимание: проект собран на 4.5.x, у вас $VERSION" >&2 ;;
esac

TEMPLATES="$HOME/Library/Application Support/Godot/export_templates"
[ -d "$TEMPLATES" ] || TEMPLATES="$HOME/.local/share/godot/export_templates"
if [ ! -d "$TEMPLATES" ]; then
  cat >&2 <<MSG
Не найдены шаблоны экспорта. Поставьте их одним из способов:
  1. Откройте проект в редакторе Godot: Editor → Manage Export Templates → Download.
  2. Или вручную распакуйте Godot_v<версия>_export_templates.tpz в
     $TEMPLATES/<версия>/
MSG
  exit 1
fi

mkdir -p "$BUILD_DIR"
echo "Импорт ресурсов…"
"$GODOT" --headless --path "$HERE" --import >/dev/null

echo "Тесты…"
"$HERE/tools/test.sh" >/dev/null || { echo "Тесты не прошли, сборка отменена" >&2; exit 1; }

echo "Экспорт пресета «$PRESET»…"
"$GODOT" --headless --path "$HERE" --export-release "$PRESET"

echo "Готово. Результат в $(cd "$BUILD_DIR" && pwd)"
ls -la "$BUILD_DIR"

cat <<'MSG'

На macOS свежескачанное приложение карантинится Gatekeeper. Для локального
запуска без подписи:
  xattr -dr com.apple.quarantine build/Khamsin.app
Для распространения нужны подпись и нотаризация — параметры в export_presets.cfg
в секции codesign/notarization.
MSG
