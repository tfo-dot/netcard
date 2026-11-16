using Random
using Printf
using Statistics

const ESPNOW_EFFECTIVE_KBPS = 580.0    # Realna przepustowość użytkowa ESP-NOW dla MTU 1400B
const PACKET_SIZE_BYTES = 1400
const SERIALIZATION_TIME_MS = (PACKET_SIZE_BYTES * 8.0) / ESPNOW_EFFECTIVE_KBPS

function simulate_bridge(; tx_q_len::Int=32, enqueue_wait_ms::Float64=10.0, burst_size::Int=25, burst_interval_ms::Float64=150.0)
    duration_ms = 10_000.0
    queue = Float64[]
    tx_free_at = 0.0
    next_burst_t = 0.0

    generated = 0
    accepted = 0
    dropped = 0
    rtts = Float64[]

    dt = 0.05
    t = 0.0

    while t < duration_ms
        if t >= next_burst_t
            for b in 0:(burst_size - 1)
                pkt_t = t + b * 0.2
                generated += 1
                q_wait = 0.0
                if length(queue) >= tx_q_len
                    oldest_finish = max(tx_free_at, queue[1] + SERIALIZATION_TIME_MS)
                    q_wait = oldest_finish - pkt_t
                end

                if length(queue) < tx_q_len
                    push!(queue, pkt_t)
                    accepted += 1
                elseif q_wait <= enqueue_wait_ms
                    push!(queue, pkt_t + q_wait)
                    accepted += 1
                else
                    dropped += 1
                end
            end
            next_burst_t += burst_interval_ms
        end

        if t >= tx_free_at && !isempty(queue)
            enq_t = popfirst!(queue)
            tx_free_at = t + SERIALIZATION_TIME_MS
            push!(rtts, tx_free_at - enq_t)
        end

        t += dt
    end

    goodput_kbps = (accepted * PACKET_SIZE_BYTES * 8.0) / duration_ms
    drop_pct = 100.0 * dropped / generated
    avg_delay = isempty(rtts) ? NaN : mean(rtts)
    max_delay = isempty(rtts) ? NaN : maximum(rtts)

    return (goodput=goodput_kbps, drop_pct=drop_pct, avg_delay=avg_delay, max_delay=max_delay)
end

println("=== SYMULACJA MOSTKA USB NCM <-> ESP-NOW (Bufferbloat vs Rozmiar Kolejki) ===")
@printf("%-38s | %10s | %9s | %11s | %11s\n",
        "Konfiguracja (tx_q_len / wait_ms)", "Goodput", "Straty", "Śr. kolejka", "Max opóźn.")
println("-"^92)

for (label, q_len, wait_ms, burst) in [
    ("1. Mała kolejka (q=8, wait=2ms)", 8, 2.0, 20),
    ("2. Średnia kolejka (q=16, wait=5ms)", 16, 5.0, 20),
    ("3. Obecny sterownik (q=32, wait=10ms)", 32, 10.0, 20),
    ("4. Duża kolejka (q=64, wait=10ms)", 64, 10.0, 20),
    ("5. Obecny sterownik + duże bursty (40)", 32, 10.0, 40)
]
    r = simulate_bridge(tx_q_len=q_len, enqueue_wait_ms=wait_ms, burst_size=burst)
    @printf("%-38s | %7.1f kb/s | %7.1f %% | %8.2f ms | %8.2f ms\n",
            label, r.goodput, r.drop_pct, r.avg_delay, r.max_delay)
end