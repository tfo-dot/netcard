using Random
using Printf

const REASM_SLOTS = 4                  # Typowa wartość REASM_SLOTS dla ESP32
const MAX_FRAG_IDX = 7                 # if (pkt->hdr.frag_idx >= 7 ...)
const MAX_FRAG_PAYLOAD = 244
const MAX_PACKET_SIZE = 1600

mutable struct ReasmSlot
    src_mac::NTuple{6, UInt8}
    fid::UInt16
    mask::UInt8
    active::Bool
    total_len::Int
    last_tick::Int
    buffer::Vector{UInt8}
    poisoned::Bool                     
end

ReasmSlot() = ReasmSlot((0,0,0,0,0,0), 0xFFFF, 0x00, false, 0, 0, zeros(UInt8, MAX_PACKET_SIZE), false)

struct FragPacket
    src_mac::NTuple{6, UInt8}
    frame_id::UInt16
    frag_idx::UInt8
    frag_total::UInt8
    payload::Vector{UInt8}
    is_malicious::Bool
end

function espnow_reasm_process_src!(slots::Vector{ReasmSlot}, pkt::FragPacket, now_tick::Int)
    if pkt.frag_idx >= MAX_FRAG_IDX || pkt.frag_total == 0 || pkt.frag_total > MAX_FRAG_IDX || length(pkt.payload) > MAX_FRAG_PAYLOAD
        return (:invalid, nothing)
    end

    slot_idx = 0
    for i in 1:length(slots)
        if slots[i].active && slots[i].fid == pkt.frame_id && slots[i].src_mac == pkt.src_mac
            slot_idx = i
            break
        end
    end

    evicted = false
    if slot_idx == 0
        oldest_tick = typemax(Int)
        for i in 1:length(slots)
            if !slots[i].active || slots[i].mask == 0
                slot_idx = i
                break
            end
            if slots[i].last_tick < oldest_tick
                oldest_tick = slots[i].last_tick
                slot_idx = i
            end
        end
        if slots[slot_idx].active && slots[slot_idx].mask != 0
            evicted = true
        end
        slots[slot_idx].active = true
        slots[slot_idx].fid = pkt.frame_id
        slots[slot_idx].mask = 0x00
        slots[slot_idx].total_len = 0
        slots[slot_idx].src_mac = pkt.src_mac
        slots[slot_idx].poisoned = false
    end

    slot = slots[slot_idx]
    slot.last_tick = now_tick

    offset = Int(pkt.frag_idx) * MAX_FRAG_PAYLOAD
    plen = length(pkt.payload)
    if offset + plen <= MAX_PACKET_SIZE
        slot.buffer[(offset + 1):(offset + plen)] .= pkt.payload
        slot.mask |= (UInt8(1) << pkt.frag_idx)
        if pkt.is_malicious
            slot.poisoned = true
        end
        if pkt.frag_idx == pkt.frag_total - 1
            slot.total_len = offset + plen
        end
    end

    expected_mask = (UInt8(1) << pkt.frag_total) - UInt8(1)
    if slot.mask == expected_mask && slot.total_len > 0
        completed_data = copy(slot.buffer[1:slot.total_len])
        was_poisoned = slot.poisoned
        slot.active = false
        slot.mask = 0x00
        slot.total_len = 0
        return (was_poisoned ? :reassembled_poisoned : :reassembled_clean, completed_data)
    end

    return (evicted ? :evicted_other : :buffered, nothing)
end

function simulate_fragmentation_attacks()
    legit_mac = (0x02, 0x00, 0x00, 0x00, 0x00, 0x01)
    rogue_mac = (0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01)

    println("=== SYMULACJA PODATNOŚCI MECHANIZMU FRAGMENTACJI (espnow_reasm_process_src) ===\n")

    println("--- Test 1: Atak wyparcia slotów (Slot Eviction / Starvation) ---")
    slots = [ReasmSlot() for _ in 1:REASM_SLOTS]
    tick = 100

    # Legalny nadawca wysyła 5 z 6 fragmentów dużego pakietu (fid = 1001)
    for idx in 0:4
        p = FragPacket(legit_mac, 1001, UInt8(idx), 6, fill(0xAA, 244), false)
        espnow_reasm_process_src!(slots, p, tick)
        tick += 1
    end
    println("Stan po 5/6 fragmentach legalnego pakietu: aktywne sloty = ", count(s -> s.active, slots))

    # Atakujący wysyła 4 pojedyncze fałszywe fragmenty (idx=0 z 2) o różnych frame_id
    evictions = 0
    for fake_fid in 2001:2004
        p = FragPacket(rogue_mac, UInt16(fake_fid), 0x00, 0x02, fill(0xFF, 10), true)
        status, _ = espnow_reasm_process_src!(slots, p, tick)
        if status == :evicted_other
            evictions += 1
        end
        tick += 1
    end

    # Legalny nadawca wysyła ostatni (6.) fragment pakietu fid = 1001
    last_p = FragPacket(legit_mac, 1001, 0x05, 0x06, fill(0xAA, 200), false)
    final_status, _ = espnow_reasm_process_src!(slots, last_p, tick)

    println("Liczba wypartych legalnych sesji: $evictions")
    println("Status ostatniego fragmentu legalnego pakietu: $final_status (pakiet przepadł mimo odebrania 6/6 fragmentów!)\n")

    println("--- Test 2: Wstrzyknięcie złośliwego fragmentu (Payload Poisoning) ---")
    slots = [ReasmSlot() for _ in 1:REASM_SLOTS]
    tick = 500

    # Legalny nadawca zaczyna pakiet fid = 42 (3 fragmenty)
    p0 = FragPacket(legit_mac, 42, 0x00, 0x03, fill(0x11, 244), false)
    espnow_reasm_process_src!(slots, p0, tick)

    # Atakujący podszywa się pod legit_mac i zgaduje kolejny inkrementowany s_tx_frame_id (42), wstrzykując fragment idx=1
    evil_p1 = FragPacket(legit_mac, 42, 0x01, 0x03, fill(0xEE, 244), true)
    espnow_reasm_process_src!(slots, evil_p1, tick + 1)

    # Legalny nadawca kończy transmisję fragmentem idx=2
    p2 = FragPacket(legit_mac, 42, 0x02, 0x03, fill(0x11, 100), false)
    status, data = espnow_reasm_process_src!(slots, p2, tick + 2)

    println("Wynik reasemblacji: $status")
    if data !== nothing
        poisoned_bytes = count(==(0xEE), data)
        println("Rozmiar złożonego pakietu IP przekazanego do stosu sieciowego: $(length(data)) B (w tym $poisoned_bytes B wstrzykniętych przez atakującego)")
    end
end

simulate_fragmentation_attacks()