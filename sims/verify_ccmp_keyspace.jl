using Printf

struct SecurityProfile
    name::String
    key_bits::Int
    nonce_bits::Int
    mac_tag_bits::Int
end

function analyze_ccmp_keyspace()
    profiles = [
        SecurityProfile("Obecny sterownik (peer.encrypt = false)", 0, 0, 0),
        SecurityProfile("ESP-NOW CCMP (AES-128, standard IEEE 802.11)", 128, 48, 64),
        SecurityProfile("Hipoteza AES-256 CCMP", 256, 48, 128)
    ]

    attacker_keys_per_sec = BigInt(10)^21
    seconds_per_year = BigInt(365) * 24 * 3600
    universe_age_years = BigFloat("1.38e10")

    k_B = BigFloat("1.380649e-23")
    T = BigFloat(300.0)
    landauer_limit_joules = k_B * T * log(BigFloat(2))
    sun_total_output_joules_per_year = BigFloat("3.828e26") * BigFloat(seconds_per_year)

    println("=== WERYFIKACJA TEORETYCZNA PRZESTRZENI KLUCZY CCMP (ESP-NOW) ===\n")

    for p in profiles
        println("Profil: $(p.name)")
        if p.key_bits == 0
            println("  -> KRYTYCZNY BRAK SZYFROWANIA (peer.encrypt = false w espnow_common.c)")
            println("  -> Przestrzeń kluczy |K| = 2^0 = 1 (transmisja otwartym tekstem, pasywny podsłuch = 0 operacji)\n")
            continue
        end

        keyspace = BigInt(2)^p.key_bits
        avg_ops_classical = keyspace ÷ 2
        years_classical = BigFloat(avg_ops_classical) / (BigFloat(attacker_keys_per_sec) * BigFloat(seconds_per_year))

        # Złożoność kwantowa (algorytm Grovera)
        grover_bits = p.key_bits ÷ 2
        grover_ops = BigInt(2)^grover_bits
        years_quantum = BigFloat(grover_ops) / (BigFloat(attacker_keys_per_sec) * BigFloat(seconds_per_year))

        # Minimalna energia termodynamiczna potrzebna do przeszukania połowy przestrzeni (granica Landauera)
        # Zakładając min. ~1000 przełączeń bramek na pojedyncze wywołanie AES
        min_energy_joules = BigFloat(avg_ops_classical) * 1000 * landauer_limit_joules
        sun_years_equivalent = min_energy_joules / sun_total_output_joules_per_year

        # Prawdopodobieństwo kolizji 48-bitowego Packet Number (Nonce) wg paradoksu urodzinowego: P ≈ q^2 / (2 * 2^48)
        packets_for_50pct_nonce_collision = sqrt(2.0 * log(2.0) * (2.0^p.nonce_bits))

        # Szansa przypadkowego odgadnięcia 64-bitowego pola MIC (Message Integrity Code) w jednej ramce
        mic_forgery_prob = 2.0^(-p.mac_tag_bits)

        @printf("  • Rozmiar przestrzeni kluczy |K| : 2^%d ≈ %.3e kombinacji\n", p.key_bits, Float64(keyspace))
        @printf("  • Czas złamania (klasyczny, 10^21/s): %.3e lat (%.2e × wiek Wszechświata)\n",
                Float64(years_classical), Float64(years_classical / universe_age_years))
        @printf("  • Złożoność kwantowa (Grover)    : 2^%d operacji (%.3e lat przy 10^21 op/s)\n",
                grover_bits, Float64(years_quantum))
        @printf("  • Min. energia (granica Landauera): %.3e J (%.2e lat całkowitej mocy Słońca)\n",
                Float64(min_energy_joules), Float64(sun_years_equivalent))
        @printf("  • Limit 48-bit Nonce (50%% kolizji) : %.3e ramek (wymaga rotacji LMK przed wyczerpaniem)\n",
                packets_for_50pct_nonce_collision)
        @printf("  • Prawdopodobieństwo sfałszowania MIC: %.3e (1 próba)\n\n", mic_forgery_prob)
    end

    println("--- Weryfikacja ograniczeń architektonicznych ESP-NOW dla trybu CCMP ---")
    max_encrypted_peers_esp32 = 17
    println("  • Maksymalna liczba zaszyfrowanych peerów w ESP-IDF: $max_encrypted_peers_esp32 (wobec ESPNOW_MAX_PEERS w RAM)")
    println("  • Ramki rozgłoszeniowe (s_broadcast_mac = FF:FF:FF:FF:FF:FF): CCMP w ESP-NOW NIE szyfruje")
    println("    ramek broadcast — pakiety discovery beacon pozostają jawne nawet po włączeniu peer.encrypt = true.")
end

analyze_ccmp_keyspace()