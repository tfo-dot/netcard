using Random
using Printf
using Statistics

const BOOT_BURST_COUNT = 3             # for (int i = 0; i < 3; i++)
const BOOT_BURST_INTERVAL_MS = 200.0   # vTaskDelay(pdMS_TO_TICKS(200))
const BEACON_INTERVAL_MS = 2000.0      # ESPNOW_BEACON_INTERVAL_MS
const TASK_WAKEUP_DELAY_MS = 3.5       # Opóźnienie wybudzenia espnow_discovery_task i transmisji

mutable struct NodeState
    id::Int
    boot_offset_ms::Float64
    known_peers::Set{Int}
    need_send_resp::Bool
    resp_target_id::Int
    resp_send_at_ms::Float64
end

function simulate_discovery_cluster(num_nodes::Int; boot_jitter_ms::Float64=50.0, seed::Int=7)
    Random.seed!(seed)
    nodes = [
        NodeState(i, rand() * boot_jitter_ms, Set{Int}(), false, 0, Inf)
        for i in 1:num_nodes
    ]

    events = Tuple{Float64, Symbol, Int, Int}[]

    for n in nodes
        for b in 0:(BOOT_BURST_COUNT - 1)
            push!(events, (n.boot_offset_ms + b * BOOT_BURST_INTERVAL_MS, :beacon, n.id, 0))
        end
        for k in 1:10
            push!(events, (n.boot_offset_ms + k * BEACON_INTERVAL_MS, :beacon, n.id, 0))
        end
    end

    sort!(events, by = x -> x[1])
    dropped_responses = 0
    full_mesh_time_ms = NaN

    while !isempty(events)
        t, ev_type, src_id, dst_id = popfirst!(events)

        if ev_type == :beacon
            for rx in nodes
                rx.id == src_id && continue
                push!(rx.known_peers, src_id)

                if rx.need_send_resp && rx.resp_target_id != src_id
                    dropped_responses += 1
                end
                rx.need_send_resp = true
                rx.resp_target_id = src_id
                if rx.resp_send_at_ms == Inf
                    rx.resp_send_at_ms = t + TASK_WAKEUP_DELAY_MS
                    push!(events, (rx.resp_send_at_ms, :send_resp, rx.id, 0))
                    sort!(events, by = x -> x[1])
                end
            end
        elseif ev_type == :send_resp
            tx = nodes[src_id]
            if tx.need_send_resp
                target = tx.resp_target_id
                tx.need_send_resp = false
                tx.resp_send_at_ms = Inf
                push!(nodes[target].known_peers, tx.id)
            end
        end

        if isnan(full_mesh_time_ms) && all(n -> length(n.known_peers) == num_nodes - 1, nodes)
            full_mesh_time_ms = t
            break
        end
    end

    return (convergence_ms=full_mesh_time_ms, overwritten_resps=dropped_responses)
end

println("=== SYMULACJA WYŚCIGU W MECHANIZMIE DISCOVERY ===")
@printf("%-36s | %18s | %22s\n", "Topologia (liczba węzłów)", "Czas pełnego mesh", "Nadpisane odpowiedzi")
println("-"^84)

for (n_nodes, jitter) in [
    (2, 10.0),
    (5, 20.0),
    (10, 20.0),
    (15, 15.0),
    (20, 10.0)
]
    r = simulate_discovery_cluster(n_nodes, boot_jitter_ms=jitter)
    @printf("%-36s | %15.1f ms | %22d\n",
            "$n_nodes węzłów (rozrzut startu $(Int(jitter)) ms)", r.convergence_ms, r.overwritten_resps)
end