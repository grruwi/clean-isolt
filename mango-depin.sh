#!/bin/bash
# clean isolt — przepina wątki pollingowe MangoHud z puli PoE na śmietnik.
#
# MangoHud to LD_PRELOAD (libMangoHud.so), NIE osobny proces — jego wątki
# (mangohud-amdgpu/hwinfo/fpsmet) żyją wewnątrz procesu gry tasksetowanego na
# 1-6,9-14. Ich periodyczne wakeupy (odczyt /sys) meszkują linię frame time.
# Jedyny sposób to runtime re-pin per-thread PO ich spawnie (init Vulkana).
#
# Wątki należą do procesu grruwi → sched_setaffinity bez sudo (ten sam user).
# Domyślnie 6,7,14,15 (śmietnik)
# Podaj inną maskę argumentem, np: ./mango-depin.sh 6,7,14,15
#
# Użycie: odpal RAZ po załadowaniu PoE do lokacji.

MASK="${1:-6,7,14,15}"

pids=$(grep -l libMangoHud /proc/*/maps 2>/dev/null | sed 's#/proc/##;s#/maps##')
moved=0
for pid in $pids; do
    [ -d "/proc/$pid/task" ] || continue
    for t in /proc/$pid/task/*; do
        tid=$(basename "$t")
        case "$(cat "$t/comm" 2>/dev/null)" in
            mangohud-*)
                if taskset -pc "$MASK" "$tid" >/dev/null 2>&1; then
                    moved=$((moved+1))
                    echo "  $tid $(cat "$t/comm") -> $MASK"
                fi
                ;;
        esac
    done
done
echo "[mango-depin] przepięto $moved wątków MangoHud na $MASK"
if [ "$moved" -eq 0 ]; then
    echo "[mango-depin] nic nie znaleziono — PoE/mango odpalone i załadowane?"
    exit 1
fi
exit 0
