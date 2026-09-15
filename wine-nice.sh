#!/bin/bash
# PoE launcher — ustawia priorytety CPU i I/O, potem odpala grę.
# Compatibility tool: forkuje ustawianie w tle, exec odpala grę.
#
# WSZYSTKO, CO SIĘ USTAWIA, STOI W TABELACH PONIŻEJ.
# PUSTE POLE = NIE RUSZAJ TEGO. Zostaje to, co ustawi kernel albo gra.

# ══════════════════════════════════════════════════════════════════════════
# 1. DYSK
# ══════════════════════════════════════════════════════════════════════════
# Każde pole niżej = plik w /sys/block/$DYSK_GRY/queue/.
# PUSTE = nie ruszaj, zostaje to, co ustawił hardware.sh albo kernel.
DYSK_GRY=nvme0n1

# bfq | none | mq-deadline | kyber | adios      bfq = ionice działa
DYSK_SCHEDULER=bfq

# ile żądań mieści kolejka programowa
DYSK_NR_REQUESTS=2048

# 0 = scalaj sąsiadujące żądania · 1 = tylko proste · 2 = wcale
DYSK_NOMERGES=0

# 0 = nie licz statystyk (iostat/iotop ślepe) · 1 = licz
DYSK_IOSTATS=0

# ile KB kernel doczytuje na zapas przy odczycie sekwencyjnym
DYSK_READ_AHEAD_KB=512

# 0 = completion tam, gdzie przerwanie · 1 = w grupie cache · 2 = na rdzeniu zgłaszającym
DYSK_RQ_AFFINITY=2

# próg dławienia zapisu w mikrosekundach · 0 = wyłączone
DYSK_WBT_LAT_USEC=10

# ══════════════════════════════════════════════════════════════════════════
# 2. WINESERVER
# ══════════════════════════════════════════════════════════════════════════
# ioklasa: rt | be | idle | (puste)      iopoziom: 0-7, 0 najwyższy | (puste)
# nice: -20..19 | (puste)                fifo: 1-99 | (puste)
WS_IOKLASA=be
WS_IOPOZIOM=0
WS_NICE=-16
WS_FIFO=55
WS_CPU=0-15

# ══════════════════════════════════════════════════════════════════════════
# 3. WĄTKI GRY  (proces Main)
# ══════════════════════════════════════════════════════════════════════════
# Wzorzec dopasowuje POCZĄTEK nazwy wątku, więc "HIGH" łapie HIGH1..HIGH5.
# Kolumny:   wzorzec   ioklasa   iopoziom   nice
# Puste kolumny zostaw puste — wtedy ta rzecz nie jest dotykana.
#
#   wzorzec          iokl  iopoz  nice
WATKI_GRY='
  HIGH               be    2      -11
  MEDIUM             be    2      -11
  LOW                be    2      -11
  Main               be    2      -11
  PathOfE:disk$      rt    0      -13
  PathOfExileStea    be    1      -13
  vkd3d_queue        rt    1      -13
  vkd3d_fence        rt    1      -13
  vkd3d-swapchain    rt    1      -13
  vkd3d-disk$        rt    0      -13
  WSI                rt    1      -13
  Bink               rt    2      -13
  FMOD               rt    2      -13
  DeadlockDetecto    be    2      -9
  mangohud           be    4      -7
  wine_              be    0      -13
  winepipewire       rt    2      -13
  data-loop          rt    0      -15
  sl.log             be    4      -9
'

# ══════════════════════════════════════════════════════════════════════════
# 4. PROCESY W TLE — mają ustąpić grze
# ══════════════════════════════════════════════════════════════════════════
TLO_NICE=10

# ══════════════════════════════════════════════════════════════════════════
# KONIEC USTAWIEŃ — niżej sama mechanika
# ══════════════════════════════════════════════════════════════════════════

klasa_na_numer() {
    case "$1" in
        rt|realtime)    echo 1 ;;
        be|best-effort) echo 2 ;;
        idle)           echo 3 ;;
        *)              echo "" ;;
    esac
}

# Ustawia jeden task wg podanych pól. Puste pole = pomijamy tę operację.
ustaw_task() {
    local tid=$1 iokl=$2 iopoz=$3 ni=$4
    local num
    num=$(klasa_na_numer "$iokl")
    if [ -n "$num" ]; then
        if [ -n "$iopoz" ]; then
            sudo ionice -c "$num" -n "$iopoz" -p "$tid" 2>/dev/null
        else
            sudo ionice -c "$num" -p "$tid" 2>/dev/null
        fi
    fi
    [ -n "$ni" ] && sudo renice -n "$ni" -p "$tid" >/dev/null 2>&1
    return 0
}

# Przechodzi WSZYSTKIE wątki procesu i stosuje pierwszy pasujący wiersz tabeli.
stosuj_watki() {
    local poe=$1 tid comm wzor iokl iopoz ni
    [ -n "$poe" ] || return 0
    [ -d "/proc/$poe/task" ] || return 0
    for t in /proc/"$poe"/task/*; do
        tid=${t##*/}
        comm=$(cat "$t/comm" 2>/dev/null) || continue
        while read -r wzor iokl iopoz ni; do
            [ -n "$wzor" ] || continue
            case "$wzor" in \#*) continue ;; esac
            case "$comm" in
                "$wzor"*) ustaw_task "$tid" "$iokl" "$iopoz" "$ni"; break ;;
            esac
        done <<< "$WATKI_GRY"
    done
}

# ── DYSK
ustaw_pole_dysku() {
    local pole=$1 wart=$2
    [ -n "$wart" ] || return 0
    sudo sh -c "echo $wart > /sys/block/$DYSK_GRY/queue/$pole" 2>/dev/null
}

# scheduler MUSI iść pierwszy i osobno: jego zmiana re-inicjalizuje kolejkę
# i kasuje nr_requests oraz read_ahead_kb ustawione wcześniej w tym samym przebiegu.
if [ -n "$DYSK_SCHEDULER" ]; then
    ustaw_pole_dysku scheduler "$DYSK_SCHEDULER"
    sleep 0.2
fi
ustaw_pole_dysku nr_requests   "$DYSK_NR_REQUESTS"
ustaw_pole_dysku nomerges      "$DYSK_NOMERGES"
ustaw_pole_dysku iostats       "$DYSK_IOSTATS"
ustaw_pole_dysku read_ahead_kb "$DYSK_READ_AHEAD_KB"
ustaw_pole_dysku rq_affinity   "$DYSK_RQ_AFFINITY"
ustaw_pole_dysku wbt_lat_usec  "$DYSK_WBT_LAT_USEC"

(
    sleep 7

    # ── WINESERVER
    WS=$(pgrep -x wineserver -n)
    if [ -n "$WS" ]; then
        [ -n "$WS_CPU" ]  && sudo taskset -pc "$WS_CPU" "$WS" >/dev/null 2>&1
        [ -n "$WS_FIFO" ] && sudo chrt -f -p "$WS_FIFO" "$WS" 2>/dev/null
        ustaw_task "$WS" "$WS_IOKLASA" "$WS_IOPOZIOM" "$WS_NICE"
    fi

    # ── WĄTKI GRY, pierwsza fala
    stosuj_watki "$(pgrep -x Main -n)"

    # ── TŁO: claude i klodzio nie mają konkurować o L3 V-Cache
    if [ -n "$TLO_NICE" ]; then
        for pid in $(pgrep -x claude) $(pgrep -f "recall_daemon|mcp_server"); do
            sudo renice -n "$TLO_NICE" -p "$pid" >/dev/null 2>&1
        done
    fi

    pkill -9 -x xalia.exe 2>/dev/null

    # ── WĄTKI GRY, druga fala: sterownik i gra tworzą wątki po starcie,
    #    pierwsza fala ich nie widziała.
    sleep 25
    stosuj_watki "$(pgrep -x Main -n)"

    # Monitor only (resctrl mon_group) — ZAKOMENTOWANE 2026-05-29: REDUNDANTNE
    # l3-status (clean isolt/diag/l3-status) auto-tworzy mon_groups i refreshuje PIDy
    # przy kazdym uruchomieniu, ze Steam cgroup. Watch dziala bez tej sekcji.
    # if [ -d /sys/fs/resctrl/mon_groups/poe ]; then
    #     for pid in $(pgrep -x Main) $(pgrep -x wineserver); do
    #         for tid in $(ls /proc/$pid/task/ 2>/dev/null); do
    #             echo "$tid" | sudo tee -a /sys/fs/resctrl/mon_groups/poe/tasks >/dev/null 2>&1
    #         done
    #     done
    # fi

    # CAT (L3 partition) — ZAKOMENTOWANE 2026-05-25 po teście:
    # Bez CAT PoE bral 81MB naturalnie (LRU wypieral claude/kwin), z CAT 78MB cap = 72MB realne.
    # Test gameplay: bez CAT "W CHUJ lepiej". Hipotezy:
    #   1. Brakuje wine helperow (services.exe, plugplay.exe, winedevice.exe) w pgrep
    #   2. CAT redukuje effective associativity per cache set -> conflict misses w hot setach
    #   3. PoE chce 81MB+ a CAT capowal 78MB
    # Mozliwy powrot — fix to wszystkie wine procesy lub szersza partycja (84MB+).
    #
    # if [ -d /sys/fs/resctrl/poe ]; then
    #     for pid in $(pgrep -x Main) $(pgrep -x wineserver); do
    #         for tid in $(ls /proc/$pid/task/ 2>/dev/null); do
    #             echo "$tid" | sudo tee -a /sys/fs/resctrl/poe/tasks >/dev/null 2>&1
    #         done
    #     done
    # fi
) &

exec "$@"
