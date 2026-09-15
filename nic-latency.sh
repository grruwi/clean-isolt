#!/bin/bash
# nic-latency.sh — tuning NIC (Intel I226-V / eno1) + affinity IRQ po NAZWIE.
# Zastępuje hardkodowane numery IRQ (100/101) z oryginalnego unitu — numery IRQ
# DRYFUJĄ między kernelami (101 wskazywało już na WiFi mt7921e zamiast NIC,
# a 100/eno1-TxRx-3 lądowało na CPU 12 = rdzeń PoE poola → IRQ storm per-pakiet
# przy każdym hicie w moby). Wszystkie kolejki eno1 → śmietnik 7,15,
# zgodnie z architekturą clean isolt (hardirq z dala od PoE poola i RT audio).

ethtool -C eno1 rx-usecs 0
ethtool -K eno1 gro off gso off tso off

for irq in $(awk -F: '/eno1/ {gsub(/ /,"",$1); print $1}' /proc/interrupts); do
    echo 6,7,14,15 > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null \
        && echo "eno1 IRQ $irq -> 0-15" \
        || echo "WARN: eno1 IRQ $irq write failed"
done
