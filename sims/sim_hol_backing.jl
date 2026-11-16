using Random
using Printf
using Statistics

const TX_QUEUE_SIZE = 32               # espnow_common_init_custom(..., 32)
const ENQUEUE_TIMEOUT_MS = 10.0        # xQueueSend(espnow_tx_q, &item, pdMS_TO_TICKS(10))
const TX_SEM_TIMEOUT_MS = 15.0         # xSemaphoreTake(espnow_tx_sem, pdMS_TO_TICKS(15))
const BEACON_INTERVAL_MS = 2000.0      # #define ESPNOW_BEACON_INTERVAL_MS 2000
const FRAGS_PER_MTU = 7                # Maksymalna liczba fragmentów (frag_idx < 7)

struct TxItem
    dest_id::Int                       # 1 = zdrowy węzeł, 2 = nieosiągalny węzeł
    arrival_ms::Float64
    frags::Int
end

function run_hol_sim(; duration_ms::Float64=10_000.0, healthy_pps::Float64=100.0, dead_peer_pps::Float64=15.0)
    queue = TxItem[]
    tx_busy_until = 0.0
    next_healthy_t = 0.0
    next_dead_t = 50.0
    next_beacon_t = 0.0

    healthy_sent = 0
    healthy_dropped_q = 0
    healthy_latencies = Float64[]

    dead_sent = 0
    dead_dropped_q = 0

    dt = 0.1
    t = 0.0

    while t < duration_ms
        if t >= next_healthy_t
            if length(queue) < TX_QUEUE_SIZE
                push!(queue, TxItem(1, t, FRAGS_PER_MTU))
            elseif (tx_busy_until - t) <= ENQUEUE_TIMEOUT_MS
                push!(queue, TxItem(1, t + ENQUEUE_TIMEOUT_MS, FRAGS_PER_MTU))
            else
                healthy_dropped_q += 1
            end
            next_healthy_t += 1000.0 / healthy_pps
        end

        if dead_peer_pps > 0 && t >= next_dead_t
            if length(queue) < TX_QUEUE_SIZE
                push!(queue, TxItem(2, t, FRAGS_PER_MTU))
            elseif (tx_busy_until - t) <= ENQUEUE_TIMEOUT_MS
                push!(queue, TxItem(2, t + ENQUEUE_TIMEOUT_MS, FRAGS_PER_MTU))
            else
                dead_dropped_q += 1
            end
            next_dead_t += 1000.0 / dead_peer_pps
        end

        if t >= next_beacon_t
            if t >= tx_busy_until
                tx_busy_until = t + 0.8 # Broadcast nie czeka na ACK
            end
            next_beacon_t += BEACON_INTERVAL_MS
        end

        if t >= tx_busy_until && !isempty(queue)
            item = popfirst!(queue)
            if item.dest_id == 1
                service_time = item.frags * 0.85
                tx_busy_until = t + service_time
                healthy_sent += 1
                push!(healthy_latencies, tx_busy_until - item.arrival_ms)
            else
                service_time = item.frags * TX_SEM_TIMEOUT_MS
                tx_busy_until = t + service_time
                dead_sent += 1
            end
        end

        t += dt
    end

    total_healthy = healthy_sent + healthy_dropped_q
    loss_pct = 100.0 * healthy_dropped_q / total_healthy
    avg_lat = isempty(healthy_latencies) ? NaN : mean(healthy_latencies)
    p99_lat = isempty(healthy_latencies) ? NaN : quantile(healthy_latencies, 0.99)

    return (sent=healthy_sent, loss_pct=loss_pct, avg_lat=avg_lat, p99_lat=p99_lat)
end

println("=== SYMULACJA HEAD-OF-LINE BLOCKING (s_tx_mutex + espnow_tx_sem) ===")
@printf("%-38s | %10s | %9s | %11s | %11s\n",
        "Scenariusz", "Odebrane", "Straty H1", "Śr. opóźn.", "P99 opóźn.")
println("-"^92)

for (label, dead_rate) in [
    ("1. Brak martwego węzła (0 pps)", 0.0),
    ("2. Rzadki ruch do martwego (2 pps)", 2.0),
    ("3. Umiarkowany ruch do martwego (8 pps)", 8.0),
    ("4. Ciągły ruch do martwego (20 pps)", 20.0)
]
    res = run_hol_sim(dead_peer_pps=dead_rate)
    @printf("%-38s | %10d | %8.1f%% | %8.2f ms | %8.2f ms\n",
            label, res.sent, res.loss_pct, res.avg_lat, res.p99_lat)
end