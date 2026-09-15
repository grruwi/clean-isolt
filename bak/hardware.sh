#!/bin/bash
# clean isolt — hardware-level tuning (system service, boot, oneshot)
#
# JEDNO ŹRÓDŁO PRAWDY. Zastępuje dawne udev rule:
#   - 60-nvme-performance.rules  (queue tuning + demote via systemd-run — psuł się exit 1)
#   - 61-gpu-performance.rules   (amdgpu affinity via systemd-run — psuł się exit 1)
#   - demote_nvme_irqs.sh        (wchłonięte tutaj)
#
# Co robi:
#   1. NVMe queue tuning (scheduler/nr_requests/read_ahead/rq_affinity/...)
#   2. NVMe IRQ threads: SCHED_FIFO 50 -> SCHED_OTHER (przez threadirqs domyślnie FIFO;
#      kolejka per-rdzeń = cache locality ZOSTAJE, ale NIE może wywłaszczać RT audio/PoE)
#   3. GPU (amdgpu) IRQ -> CPU 6,7,14,15 + FIFO 77 (garbage cores, pod audio 88/83 nad kwin/wine)
#   4. NVMe admin queue (q0) -> CPU 0,8 (lekki management, z dala od 7,15)
#
# CZEGO NIE RUSZA:
#   - pp_power_profile_mode: właścicielem jest LACT (lactd), trzyma CUSTOM. Nie nadpisujemy.
#   - reszta hard IRQ (eno1/xhci/ahci): kernel rozrzuca na 7,15 przez cmdline irqaffinity=7,15.
#   - nvme-*-wq rescuery: zostają na nice -20 (kernelowy default, nie są na FIFO, nie przeszkadzają).
#
# Wywoływany przez: /etc/systemd/system/hardware.service (After=multi-user.target)
# Best-effort: pojedynczy nieudany zapis NIE przerywa skryptu (brak set -e celowo).

log() { echo "[hardware] $*"; }

# --- 1. NVMe queue tuning -----------------------------------------------------
for dev in /sys/block/nvme*n*; do
    [ -d "$dev" ] || continue
    q="$dev/queue"
    name=$(basename "$dev")
    # 2026-06-17: none (gołe — single-CCD top NVMe, brak kontencji = kyber to narzut bez zysku;
    # mniejsze initial-burst spajki, szybciej gaśnie). wbt=0 (storm killer — wbt dławił
    # shader-compile writes), rq_aff=1, nomerges=0. Zob. memory project-poe-latency-debug.
    # UWAGA: stare none/rq2/nomerges2 klobrowało — to było SKAŻONE złym rq/nomerges, NIE ten sam none.
    [ -w "$q/scheduler" ]      && echo none  > "$q/scheduler"
    [ -w "$q/nr_requests" ]    && echo 512  > "$q/nr_requests"
    [ -w "$q/nomerges" ]       && echo 0    > "$q/nomerges"
    [ -w "$q/iostats" ]        && echo 0    > "$q/iostats"
    [ -w "$q/read_ahead_kb" ]  && echo 128  > "$q/read_ahead_kb"
    [ -w "$q/rq_affinity" ]    && echo 1    > "$q/rq_affinity"
    [ -w "$q/wbt_lat_usec" ]   && echo 0    > "$q/wbt_lat_usec"
    log "NVMe queue tuning -> $name (none/512/ra128/rq_aff1/wbt0/nomerges0)"
done

# --- 2. NVMe IRQ threads: FIFO -> SCHED_OTHER ---------------------------------
demoted=0
for tid in $(pgrep -i 'irq/.*nvme'); do
    chrt -o -p 0 "$tid" 2>/dev/null && demoted=$((demoted+1))
done
log "NVMe IRQ threads demoted FIFO->OTHER: $demoted"

# --- 3. GPU (amdgpu) IRQ -> CPU 6,7,14,15, FIFO 77 -----------------------------------
#   FIFO 77: threadirqs domyslnie daje 50; podnosimy do 77 zeby GPU IRQ wyprzedzal
#   inne RT (kwin FIFO 45, wine 41) ALE zostawal pod audio data-loop (FIFO 88/83)
#   na wspolnych garbage cores 6,7,14,15 (2026-07-05).
for irq in $(grep -E "amdgpu" /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
    echo 0,8 > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null && \
        log "GPU IRQ $irq -> CPU 6,7,14,15" || \
        log "WARN: GPU IRQ $irq write failed"
    for tid in $(pgrep -f "irq/$irq-amdgpu"); do
        chrt -f -p 77 "$tid" 2>/dev/null && log "GPU IRQ thread $tid ($irq) -> FIFO 77" || \
            log "WARN: GPU IRQ thread $tid chrt failed"
    done
done

# --- 3b. USB (xhci) IRQ -> CPU 6,7,14,15 --------------------------------------------
#   zdejmujemy rdzen 0 (kernel) z maski USB zeby wtyk/ruch USB nie budzil kernel core;
#   laduje na garbage cores razem z GPU/audio (2026-07-05).
for irq in $(grep -iE "xhci" /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
    echo 6,7,14,15 > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null && \
        log "USB xhci IRQ $irq -> CPU 6,7,14,15" || \
        log "WARN: USB IRQ $irq write failed"
done

# --- 4. NVMe admin queue (q0) -> CPU 0,8 -------------------------------------
for irq in $(grep nvme0q0 /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
    echo 0,8 > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null
done
log "NVMe admin queue (q0) -> CPU 0,8"

log "DONE $(date +%H:%M:%S)"
