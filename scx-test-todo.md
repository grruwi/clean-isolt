# scx_rusty — macierz testowa flag (2026-06-10)

Stałe w każdym teście: `--perf 1024 --kthreads-local`, irq na 7,15 (lub 0,7,8,15), PoE taskset 1-6,9-14.
**Każdy set ×2: KDE AllowTearing OFF i ON** (od Protona 11 present mode/frame buffer = istotne).
Metryka: reset licznika mango → patrz **0.1% low** + w scxtop czy pojedynczy rdzeń PoE się sytuuje (saturacja).
Present Mode w mango ma pokazywać IMMEDIATE (vkd3d frame buffer na immediate, nie wymuszony FIFO).

## Wyłączniki migracji (defaulty — ZAPAMIĘTAJ):
- `--no-load-balance` — periodyczny LB (default ON)
- `--greedy-threshold 0` — kradzież idle (default 1 = ON)
- `--direct-greedy-under 0` — push na idle <N% (default 90 = ON, 0 = disable)
- fifo/vtime = TYLKO kolejność, NIE migracja.

---

## ✅ WINNER (lobby, do potwierdzenia w delwie)
- [ ] **A — pełna sterylność:** `--cache-level 2 --no-load-balance --greedy-threshold 0 --direct-greedy-under 0 --fifo-sched`
      → STRESS w delwie + duży młyn. Patrz: czy któryś rdzeń PoE saturuje (=zator). Jak pacing trzyma — to jest baseline.

## FAZA 1 — minimalna migracja JEŚLI A zatka pod obciążeniem (dodawać po jednej):
- [ ] **B:** A + `--greedy-threshold 1` (idle rdzeń kradnie 1 task z sąsiada w puli; affinity trzyma w PoE)
- [ ] **C:** A + `--greedy-threshold 2`
- [ ] **D:** A + `--direct-greedy-under 90` (push zamiast kradzieży)
      → cel: najtańsza migracja która rozładuje hotspot bez psucia frame pacingu z A.

## FAZA 2 — nowa oś: vtime vs fifo PRZY no-balance (nigdy nie testowane razem):
- [ ] **E:** `--cache-level 2 --no-load-balance --greedy-threshold 0 --direct-greedy-under 0` (vtime, bez fifo)
      → czy fairness vtime pomaga czy szkodzi gdy migracja i tak wyłączona?
- [ ] **F:** E + `--greedy-threshold 1`

## FAZA 3 — ścieżka "wspólny dsq balansuje" (cache-level 3):
- [ ] **G:** `--cache-level 3 --no-load-balance --greedy-threshold 0 --fifo-sched`
      → jedna domena = wszystkie rdzenie ciągną z jednej kolejki (spread bez migracji).
      Czy shared-dsq pull bije per-core wyspy z A pod obciążeniem?

## Referencyjne (dla pełnego obrazu, niski priorytet):
- [ ] **H:** `--cache-level 2 --fifo-sched` (default LB+greedy on) — stary "dobry" set, jako punkt odniesienia
- [ ] **I:** `--cache-level 2` goły (vtime, default migracja) — ile faktycznie dokłada fifo+sterylność

---

## Polowanie na bottleneck spajków (osobny wątek, NIE shadery):
Spajki na 5 mobach z wygrzanym cache = przepustowość/submisja, nie kompilacja.
Z setem A (zero migracji) scheduler jest oczyszczony → jeśli spajki zostają, winny jest:
- vkd3d submission path (narzut translacji D3D12→VK na nowych encjach)
- alokacje/page faults na spawnie moba (THP=madvise, sprawdzić czy PoE bierze huge pages)
- IOD/mem bandwidth burst (alokacja + GPU upload konkurują na single CCD)
Watch: mango frametime graph vs scxtop softirq/io_wait w momencie spajku.
Baza: IOMMU disabled (było DUŻO gorzej z enabled).
