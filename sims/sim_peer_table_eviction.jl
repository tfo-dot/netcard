using Random
using Printf

const ESPNOW_MAX_PEERS = 20            # Sprzętowy limit ESP-NOW dla listy peerów
const PEER_TIMEOUT_MS = 10_000         # ESPNOW_PEER_TIMEOUT_MS
const BEACON_INTERVAL_MS = 2000        # ESPNOW_BEACON_INTERVAL_MS

mutable struct PeerEntry
    mac::UInt64
    ip::UInt32
    last_seen::Int
    active::Bool
    is_static::Bool
end

PeerEntry() = PeerEntry(0, 0, 0, false, false)

function peer_table_touch!(peers::Vector{PeerEntry}, mac::UInt64, now_ms::Int, is_static::Bool=false)
    for p in peers
        if p.active && p.mac == mac
            p.last_seen = now_ms
            return :updated
        end
    end

    free_idx = findfirst(p -> !p.active, peers)
    evicted_mac = UInt64(0)

    if free_idx === nothing
        oldest_tick = typemax(Int)
        for i in 1:length(peers)
            if !peers[i].is_static && peers[i].last_seen < oldest_tick
                oldest_tick = peers[i].last_seen
                free_idx = i
            end
        end
        if free_idx !== nothing
            evicted_mac = peers[free_idx].mac
        else
            return :table_full_static
        end
    end

    peers[free_idx] = PeerEntry(mac, 0x0A000002, now_ms, true, is_static)
    return evicted_mac != 0 ? (:evicted, evicted_mac) : :added
end

function resolve_dest_is_broadcast(peers::Vector{PeerEntry}, target_mac::UInt64)
    for p in peers
        if p.active && p.mac == target_mac
            return false
        end
    end
    return true
end

function run_peer_eviction_sim(; spoof_pps::Int=50, legit_static::Bool=false)
    Random.seed!(123)
    peers = [PeerEntry() for _ in 1:ESPNOW_MAX_PEERS]
    legit_peer_mac = UInt64(0x020000000002)

    peer_table_touch!(peers, legit_peer_mac, 0, legit_static)

    duration_ms = 10_000
    broadcast_fallback_packets = 0
    total_legit_tx = 0
    eviction_count = 0
    next_spoof_mac = UInt64(0xDEAD00000001)

    for t in 1:duration_ms
        if t % BEACON_INTERVAL_MS == 0
            peer_table_touch!(peers, legit_peer_mac, t, false)
        end

        if spoof_pps > 0 && (t % max(1, div(1000, spoof_pps)) == 0)
            res = peer_table_touch!(peers, next_spoof_mac, t, false)
            next_spoof_mac += 1
            if res isa Tuple && res[1] == :evicted && res[2] == legit_peer_mac
                eviction_count += 1
            end
        end

        if t % 10 == 0
            total_legit_tx += 1
            if resolve_dest_is_broadcast(peers, legit_peer_mac)
                broadcast_fallback_packets += 1
            end
        end
    end

    fallback_pct = 100.0 * broadcast_fallback_packets / total_legit_tx
    return (evictions=eviction_count, fallback_pct=fallback_pct)
end

println("=== SYMULACJA WYCZERPANIA TABLICY SĄSIADÓW (s_peers Eviction & Broadcast Fallback) ===")
@printf("%-48s | %12s | %18s\n", "Konfiguracja i natężenie ataku", "Wypchnięcia", "Ruch zdegradowany")
println("-"^84)

for (desc, pps, is_stat) in [
    ("1. Brak ataku (dynamiczny peer)", 0, false),
    ("2. Słaby MAC Flood: 15 pps (dynamiczny peer)", 15, false),
    ("3. Średni MAC Flood: 100 pps (dynamiczny peer)", 100, false),
    ("4. Silny MAC Flood: 500 pps (dynamiczny peer)", 500, false),
    ("5. Silny MAC Flood: 500 pps (is_static = true)", 500, true)
]
    r = run_peer_eviction_sim(spoof_pps=pps, legit_static=is_stat)
    @printf("%-48s | %12d | %16.1f %%\n", desc, r.evictions, r.fallback_pct)
end