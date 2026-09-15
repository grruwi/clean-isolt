#!/bin/bash
# Uwolnij Xwayland — dziedziczy maskę kwin_wayland (historycznie 7,15, obecnie 0,8),
# ale apki X11 (gry, discord) muszą mieć dostęp do wszystkich rdzeni.
#
# 2026-05-30: usunięto `chrt -f -p 99 kwin`. Trzymamy się ananicy convention
# LowLatency_RT = tylko nice -12 + best-effort, BEZ SCHED_FIFO.
# Kwin nice/ioclass ustawia post-plasma.sh per ananicy.

# Uwolnij Xwayland (czeka aż wstanie)
for i in {1..30}; do
    PID=$(pgrep -x Xwayland)
    if [[ -n "$PID" ]]; then
        taskset -cp 0-15 "$PID" &>/dev/null
        exit 0
    fi
    sleep 1
done
exit 1
