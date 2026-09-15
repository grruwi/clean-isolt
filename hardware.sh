#!/bin/bash

log() { echo "[hardware] $*"; }

# ── KOLEJKI NVMe ──────────────────────────────────────────────────────────
# PUSTE = nie ruszaj. scheduler idzie PIERWSZY i osobno: jego zmiana
# re-inicjalizuje kolejkę i kasuje nr_requests oraz read_ahead_kb ustawione
# w tym samym przebiegu.
NVME_SCHEDULER=bfq
NVME_NR_REQUESTS=2048
NVME_NOMERGES=0
NVME_IOSTATS=0
NVME_READ_AHEAD_KB=512
NVME_RQ_AFFINITY=2
NVME_WBT_LAT_USEC=10

for dev in /sys/block/nvme*n*; do
    [ -d "$dev" ] || continue
    q="$dev/queue"
    name=$(basename "$dev")

    if [ -n "$NVME_SCHEDULER" ] && [ -w "$q/scheduler" ]; then
        echo "$NVME_SCHEDULER" > "$q/scheduler"
        sleep 0.2
    fi
    for para in "nr_requests:$NVME_NR_REQUESTS" \
                "nomerges:$NVME_NOMERGES" \
                "iostats:$NVME_IOSTATS" \
                "read_ahead_kb:$NVME_READ_AHEAD_KB" \
                "rq_affinity:$NVME_RQ_AFFINITY" \
                "wbt_lat_usec:$NVME_WBT_LAT_USEC"; do
        pole=${para%%:*}; wart=${para#*:}
        [ -n "$wart" ] && [ -w "$q/$pole" ] && echo "$wart" > "$q/$pole"
    done

    # Log czyta z sysfs PO zapisie — nie melduje tego, co chcieliśmy ustawić.
    czyt() { cat "$q/$1" 2>/dev/null; }
    log "NVMe $name -> sched=$(czyt scheduler | grep -o '\[.*\]') nr_req=$(czyt nr_requests) ra=$(czyt read_ahead_kb) rq_aff=$(czyt rq_affinity) wbt=$(czyt wbt_lat_usec) iostats=$(czyt iostats) nomerges=$(czyt nomerges)"
done

demoted=0
for tid in $(pgrep -i 'irq/.*nvme'); do
    chrt -o -p 0 "$tid" 2>/dev/null && demoted=$((demoted+1))
done
log "NVMe IRQ threads demoted FIFO->OTHER: $demoted"

for irq in $(grep -E "amdgpu" /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
    echo 0,8 > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null && \
        log "GPU IRQ $irq -> CPU 0,8" || \
        log "WARN: GPU IRQ $irq write failed"
    for tid in $(pgrep -f "irq/$irq-amdgpu"); do
        chrt -f -p 77 "$tid" 2>/dev/null && log "GPU IRQ thread $tid ($irq) -> FIFO 77" || \
            log "WARN: GPU IRQ thread $tid chrt failed"
    done
done

for irq in $(grep -iE "xhci" /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
    echo 6,7,14,15 > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null && \
        log "USB xhci IRQ $irq -> CPU 6,7,14,15" || \
        log "WARN: USB IRQ $irq write failed"
done

for irq in $(grep nvme0q0 /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
    echo 0,8 > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null
done
log "NVMe admin queue (q0) -> CPU 0,8"

log "DONE $(date +%H:%M:%S)"
