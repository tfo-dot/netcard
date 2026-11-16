using Random
using Printf
using Statistics

const TX_QUEUE_SIZE = 32               # espnow_common_init_custom(..., 32)
const ENQUEUE_TIMEOUT_MS = 10.0        # xQueueSend(espnow_tx_q, &item, pdMS_TO_TICKS(10))
const TX_SEM_TIMEOUT_MS = 15.0         # xSemaphoreTake(espnow_tx_sem, pdMS_TO_TICKS(15))
const MAX_NO_MEM_RETRIES = 20          # int retries = 20;
const NO_MEM_RETRY_DELAY_MS = 1.0      # vTaskDelay(pdMS_TO_TICKS(1))
const MAX_FRAGMENTS = 7                # pkt->hdr.frag_idx < 7
const MAX_FRAG_PAYLOAD = 244           # 250B limit ESP-NOW - 6B frag_hdr_t
const MTU_BYTES = 1500                 # Standardowy pakiet IPv4 z USB NCM

struct SimConfig
    duration_ms::Float64
    app_packet_rate_pps::Float64       
    packet_size_bytes::Int
    channel_per::Float64               
    dos_attack_pps::Float64            
end

function run_dos_jamming_sim(cfg::SimConfig; seed::Int=42)
    Random.seed!(seed)

    frags_per_pkt = ceil(Int, cfg.packet_size_bytes / MAX_FRAG_PAYLOAD)
    @assert frags_per_pkt <= MAX_FRAGMENTS "Pakiet przekracza limit 7 fragmentów sterownika!"

    tx_queue = Float64[]

    # Czasy zdarzeń
    next_app_pkt_time = 0.0
    tx_task_free_at = 0.0

    # Statystyki
    total_generated = 0
    dropped_queue_full = 0
    dropped_tx_error = 0
    corrupted_by_jamming = 0
    delivered_packets = 0
    total_latency_ms = 0.0

    dt = 0.1
    t = 0.0

    dos_channel_load = clamp(cfg.dos_attack_pps / 2500.0, 0.0, 0.98)

    while t < cfg.duration_ms
        if t >= next_app_pkt_time
            total_generated += 1
            if length(tx_queue) < TX_QUEUE_SIZE
                push!(tx_queue, t)
            else
                if (tx_task_free_at - t) <= ENQUEUE_TIMEOUT_MS
                    push!(tx_queue, t + ENQUEUE_TIMEOUT_MS)
                else
                    dropped_queue_full += 1
                end
            end
            next_app_pkt_time += 1000.0 / cfg.app_packet_rate_pps
        end

        if t >= tx_task_free_at && !isempty(tx_queue)
            arrival_t = popfirst!(tx_queue)
            pkt_tx_time = 0.0
            tx_failed = false
            pkt_lost_in_air = false

            for frag in 1:frags_per_pkt
                retries = 0
                while rand() < dos_channel_load && retries < MAX_NO_MEM_RETRIES
                    retries += 1
                    pkt_tx_time += NO_MEM_RETRY_DELAY_MS
                end

                if retries == MAX_NO_MEM_RETRIES
                    tx_failed = true
                    break
                end

                if rand() < (cfg.channel_per + dos_channel_load * 0.4)
                    pkt_tx_time += TX_SEM_TIMEOUT_MS * 0.5
                    pkt_lost_in_air = true
                else
                    pkt_tx_time += 0.85
                end
            end

            tx_task_free_at = t + pkt_tx_time

            if tx_failed
                dropped_tx_error += 1
            elseif pkt_lost_in_air
                corrupted_by_jamming += 1
            else
                delivered_packets += 1
                total_latency_ms += (tx_task_free_at - arrival_t)
            end
        end

        t += dt
    end

    sim_seconds = cfg.duration_ms / 1000.0
    goodput_kbps = (delivered_packets * cfg.packet_size_bytes * 8.0) / 1000.0 / sim_seconds
    avg_latency = delivered_packets > 0 ? (total_latency_ms / delivered_packets) : NaN
    loss_rate = total_generated > 0 ? 100.0 * (1.0 - delivered_packets / total_generated) : 0.0

    return (
        goodput_kbps = goodput_kbps,
        loss_pct = loss_rate,
        avg_latency_ms = avg_latency,
        drop_q = dropped_queue_full,
        drop_nomem = dropped_tx_error,
        drop_air = corrupted_by_jamming
    )
end

# Uruchomienie scenariuszy porównawczych
scenarios = [
    ("1. Warunki idealne (brak DoS, PER=1%)",        SimConfig(10_000.0, 120.0, 1400, 0.01, 0.0)),
    ("2. Umiarkowane zakłócenia RF (PER=15%)",      SimConfig(10_000.0, 120.0, 1400, 0.15, 0.0)),
    ("3. Silne zakłócenia RF (PER=35%)",            SimConfig(10_000.0, 120.0, 1400, 0.35, 0.0)),
    ("4. Lekki atak DoS (800 pps) + PER=5%",        SimConfig(10_000.0, 120.0, 1400, 0.05, 800.0)),
    ("5. Silny atak DoS (2200 pps) + PER=5%",       SimConfig(10_000.0, 120.0, 1400, 0.05, 2200.0))
]

println("=== SYMULACJA WPŁYWU ATAKU DoS I ZAKŁÓCEŃ NA PRZEPUSTOWOŚĆ ESP-NOW ===")
@printf("%-42s | %10s | %9s | %11s | %s\n", "Scenariusz", "Goodput", "Straty", "Opóźnienie", "Przyczyna strat (Q / NoMem / Air)")
println("-"^105)

for (name, cfg) in scenarios
    res = run_dos_jamming_sim(cfg)
    @printf("%-42s | %7.1f kb/s | %7.1f %% | %8.2f ms | %d / %d / %d\n",
            name, res.goodput_kbps, res.loss_pct, res.avg_latency_ms,
            res.drop_q, res.drop_nomem, res.drop_air)
end