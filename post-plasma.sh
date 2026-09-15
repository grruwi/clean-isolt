#!/bin/bash
# clean isolt — runtime tuning po starcie KDE (user service, plasma-workspace.target)
#
# Co robi:
#   1. Pinuje kwin/plasmashell na 0,8 + audio runtime backup (drop-iny robią to przy starcie).
#   2. Aplikuje ananicy convention dla rzeczy które ananicy by zrobiło, gdyby działało:
#      - LowLatency_RT (nice -12, ioclass best-effort): kwin, Xwayland, krunner
#      - nice -6: plasmashell (osobna reguła ananicy)
#      - BG_CPUIO (nice 16, sched_idle, ioclass idle): baloo_file, kded6, kaccess, ksmserver
#      - BG_CPUIO + taskset 7,15 + resctrl: claude (node binary)
#      - Service (nice 10, ioclass best-effort, ionice 6): kwalletd6
#   3. Pinuje klodzio na 7,15 + wpis do resctrl/klodzio/tasks.
#   4. 3 rundy z sleep 10/30 żeby złapać late spawny (autostart aplikacji).
#
# 2026-05-30: Rozszerzone z ananicy convention 1.1.35-1 (cachyos-ananicy-rules).
# Daemon ananicy się NIE URUCHAMIA — ten skrypt robi to co by zrobił.
# Pełna tabela typów w /etc/ananicy.d/00-types.types.
#
# Wywoływany przez: ~/.config/systemd/user/post-plasma.service

apply_pins() {
    # ====================================================================
    # LowLatency_RT (ananicy): nice -12 + ioclass best-effort priority 0
    # ====================================================================

    # --- kwin -> 0,8 (WSZYSTKIE wątki, -acp) + LowLatency_RT ---
    # Kwin NIE ma resctrl CTRL group — siedzi w ROOT, pełen dostęp do 96MB L3.
    # 2026-07-05: zawężony z 0-8 na 0,8 (kernel+audio rdzenie); -acp zamiast -pc
    #   bo -pc łapało tylko główny wątek, dzieci/thready zostawały na 0-15.
    # 2026-05-30: usunięto chrt -o (ananicy nie rusza schedulera, tylko nice+ioclass).
    # 2026-09-02: chrt WRACA — ananicy zostaje wyłączony na stałe, więc FIFO 40
    #   musi wejść stąd, inaczej kwin siedzi na SCHED_RR prio 1 (sam sobie tak daje).
    for pid in $(pgrep -x kwin_wayland); do
        sudo taskset -acp 0,8 "$pid" >/dev/null
        sudo chrt -f -p 40 "$pid" >/dev/null
        sudo renice -n -12 -p "$pid" >/dev/null
        sudo ionice -c 2 -n 0 -p "$pid" >/dev/null
    done

    # --- plasmashell -> 0,8 (WSZYSTKIE wątki, -acp) + FIFO 40 + nice -13 ---
    # 2026-09-02: FIFO 40 jak kwin (polecenie grruwiego). Nice zostaje jako ślad,
    #   pod FIFO jest ignorowany — wraca dopiero gdyby chrt kiedyś wypadł.
    for pid in $(pgrep -x plasmashell); do
        sudo taskset -acp 0,8 "$pid" >/dev/null
        sudo chrt -f -p 40 "$pid" >/dev/null
        sudo renice -n -12 -p "$pid" >/dev/null
    done

    # --- Xwayland -> FIFO 40 + nice -12 + ioclass best-effort, taskset robi free-xwayland.sh ---
    # 2026-09-07: FIFO 40 jak kwin/plasmashell (polecenie grruwiego).
    for pid in $(pgrep -x Xwayland); do
        sudo chrt -f -p 40 "$pid" >/dev/null
        sudo renice -n -12 -p "$pid" >/dev/null
        sudo ionice -c 2 -p "$pid" >/dev/null
    done

    # --- krunner -> LowLatency_RT (Alt+Space search instant) ---
    for pid in $(pgrep -x krunner); do
        sudo renice -n -4 -p "$pid" >/dev/null
        sudo ionice -c 2 -n 0 -p "$pid" >/dev/null
    done

    # ====================================================================
    # audio stack -> CPU 0,8 (cały P0, drop-iny robią to przy starcie, runtime backup)
    # 2026-05-30: poszerzone z samego 8 na 0,8 — audio czasem potrzebuje SMT partnera.
    # ====================================================================
    for pid in $(pgrep -x 'pipewire|wireplumber|pipewire-pulse'); do
        sudo taskset -acp 0,8 "$pid" >/dev/null 2>&1
    done

    # ====================================================================
    # BG_CPUIO (ananicy): nice 16 + sched_idle + ioclass idle
    # KDE background daemons — niech siedzą cicho gdy CPU coś robi.
    # ====================================================================
    for name in baloo_file kded6 kaccess ksmserver; do
        for pid in $(pgrep -x "$name"); do
            sudo renice -n 16 -p "$pid" >/dev/null
            sudo chrt -i -p 0 "$pid" 2>/dev/null
            sudo ionice -c 3 -p "$pid" 2>/dev/null
        done
    done

    # ====================================================================
    # Service (ananicy): nice 10 + ioclass best-effort, ionice 6
    # ====================================================================
    for pid in $(pgrep -x kwalletd6); do
        sudo renice -n 10 -p "$pid" >/dev/null
        sudo ionice -c 2 -n 6 -p "$pid" >/dev/null
    done

    # ====================================================================
    # Claude (node = BG_CPUIO per ananicy) + klodzio (custom, recall reaktywne)
    # ====================================================================
    # 2026-05-26: claude/klodzio z dala od kwin+audio — wolniejsze rdzenie OK,
    # ważniejsze że nie zalewają cache który teraz dzielą kwin+audio+GPU IRQ.
    #
    # 2026-05-30: ananicy mówi node = BG_CPUIO (nice 16, sched_idle, idle ioclass).
    # Claude jest Node.js — aplikujemy to. Klodzio (Python recall daemon) zostaje
    # na default nice 0, bo MUSI reagować na recall hooks per prompt.
    #
    # UWAGA 2026-05-26: pgrep -x claude NIE DZIAŁA bo claude binary po update
    # nazywa się "claude.original" (po przejściu przez wrapper).
    #
    # 2026-05-30: cmdline ŚWIEŻO uruchomionego claude'a to ścieżka symlinka
    # (/home/grruwi/.local/bin/claude.original.symlink) — NIE zawiera "claude/versions".
    #
    # 2026-06-01: instalka przeniesiona do ~/.claude/local/ (XDG redirect). Wrapper
    # claude-tune wskazuje teraz na ~/.claude/local/claude — comm = "claude", cmdline
    # zawiera ".claude/local/claude". Dodajemy trzy wzorce dla redundancji:
    #   1. legacy: comm == "claude.original" (gdyby ktoś jeszcze odpalał stary symlink)
    #   2. new:    cmdline zawiera "/.claude/local/claude" (świeży wrapper)
    #   3. raw:    cmdline zawiera "claude/versions/X" (bezpośrednie wywołanie binarki)
    #
    # klodzio_parents rozszerzone na całe /Dokumenty/klodzio/.*\.py żeby łapać
    # też helpery (family-watch.py, gemini_ingest.py, etc.) gdyby uruchamiane
    # standalone. mcp_server.py jest per-session child claude'a.
    claude_parents="$(pgrep -x claude.original 2>/dev/null) $(pgrep -f '/\.claude/local/claude' 2>/dev/null) $(pgrep -f 'claude/versions/[0-9]' 2>/dev/null)"
    klodzio_parents=$(pgrep -f "/Dokumenty/klodzio/.*\.py")
    all_children=""
    for p in $claude_parents $klodzio_parents; do
        all_children="$all_children $(pgrep -P $p)"
    done

    # --- taskset 6,7,8,14,15 (śmietnik + r8, bez r0 kernela) + resctrl dla claude+klodzio ---
    # 2026-07-05: z 1-7,9-15 na 6,7,8,14,15 — claude trzyma się garbage cores + r8,
    #   nie rozłazi się po arenie gry (0-5,9-13); r0 (kernel) zostawiony czysty.
    for pid in $claude_parents $klodzio_parents $all_children; do
        sudo taskset -acp 6,7,8,14,15 "$pid" >/dev/null 2>&1
        echo "$pid" | sudo tee /sys/fs/resctrl/klodzio/tasks >/dev/null 2>&1
    done

    # --- Claude TYLKO: BG_CPUIO (ananicy node convention) ---
    # Klodzio (recall_daemon) świadomie zostaje na default — reaguje na hooks.
    for pid in $claude_parents; do
        sudo renice -n 16 -p "$pid" >/dev/null
        sudo chrt -i -p 0 "$pid" 2>/dev/null
        sudo ionice -c 3 -p "$pid" 2>/dev/null
    done
}

echo "[post-plasma] RUNDA 1 start $(date +%T)"
apply_pins

echo "[post-plasma] sleep 10..."
/usr/bin/sleep 10
echo "[post-plasma] RUNDA 2 start $(date +%T)"
apply_pins

echo "[post-plasma] sleep 30..."
/usr/bin/sleep 30
echo "[post-plasma] RUNDA 3 start $(date +%T)"
apply_pins

echo "[post-plasma] DONE $(date +%T)"
