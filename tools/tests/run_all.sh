#!/bin/sh
# Собирает и запускает все C-тесты на всех сценах. Запуск из корня проекта: sh tools/tests/run_all.sh
# Если задана переменная DUMP_ASSETS (папка Assets дампа игры), дополнительно сверяется поза персонажа с эталоном на Python.
set -e
cd "$(dirname "$0")/../.."
T=tools/tests; R=Resources/scenes; B=/tmp/cg_tests; mkdir -p $B
CC="gcc -std=c99 -O2 -Wall -Wextra -Isrc"
$CC $T/cgs_check.c -o $B/cgs_check -lm
$CC $T/player_check.c src/Collision.c -o $B/player_check -lm
$CC $T/ray_check.c src/Collision.c -o $B/ray_check -lm
$CC $T/weapon_check.c src/Weapon.c -o $B/weapon_check -lm
$CC $T/rig_check.c src/Rig.c -o $B/rig_check -lm
$CC $T/bot_check.c src/Bot.c src/Collision.c -o $B/bot_check -lm
$CC $T/audio_check.c src/AudioBank.c -o $B/audio_check -lm
fail=0
echo "== логика оружия"; $B/weapon_check | tail -1 || fail=1
echo "== риг персонажа"
$B/rig_check Resources/characters/rudy.cgr > $B/rig_c.txt || fail=1
grep '^BLEND' $B/rig_c.txt
if [ -n "$DUMP_ASSETS" ]; then python3 $T/rig_compare.py "$DUMP_ASSETS" $B/rig_c.txt || fail=1; fi
echo "== звук"; $B/audio_check Resources/audio | tail -1 || fail=1
python3 $T/audio_plist_check.py Resources || fail=1
echo "== враги (синтетический мир)"; $B/bot_check synthetic | tail -1 || fail=1
for s in $(ls $R/*.cgs | xargs -n1 basename | sed 's/\.cgs$//'); do
  echo "== $s"
  $B/cgs_check $R/$s.cgs >/dev/null 2>$B/cgs.log || { cat $B/cgs.log; fail=1; }
  tail -1 $B/cgs.log
  $B/player_check $R $s | grep -E "макс. проникновение" || fail=1
  $B/ray_check $R $s 20000 || fail=1
  $B/bot_check scene $R $s 60 | grep -v "точек в" || fail=1
done
[ $fail -eq 0 ] && echo "ВСЕ ТЕСТЫ ПРОЙДЕНЫ" || { echo "ЕСТЬ ОШИБКИ"; exit 1; }
