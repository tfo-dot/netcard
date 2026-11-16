#set page(
	paper: "a4",
	margin: (top: 3.5cm, bottom: 3.5cm, left: 3cm, right: 2cm)
)

#set text(
  font: "Times New Roman",
  size: 12pt,
  lang: "pl",
  region: "pl",
)

#set par(
  justify: true,
  leading: 0.65em,
  first-line-indent: 1.25cm,
)

#show figure.caption: set text(font: "Times New Roman", size: 10pt)
#show figure.where(kind: table): set figure.caption(position: top)

#set heading(numbering: "1.1.")
#show heading: it => {
  v(0.6em)
  it
  v(0.4em)
}

#align(center)[

  #image("awl.png", height: 3.81cm, width: 8.12cm)

  #text(size: 18pt)[Inżynieria Internetu Rzeczy] \
  \

  #text(weight: "bold", size:16pt)[Projekt: stworzenie karty sieciowej opartej na protokole ESPNOW] \ 
  \
  \
  \
  \
  \
  Radosław Partyka - s11130\@edukacja.awl.edu.pl\
  Wiktor Kowalski - s11125\@edukacja.awl.edu.pl\
  \
  \
  \
  \
  \
Akademia Wojsk Lądowych \
imienia Generała Tadeusza Kościuszki\
we Wrocławiu \
\
\
\
\
\
\
\
\
  Wrocław #datetime.today().display("[day]/[month]/[year]")\
]

#set page(
	header: par(leading: 0.5em)[Akademia Wojsk Lądowych \ Katedra Informatyki i Nowoczesnych Technologii.] + line(length: 100%),
	footer: context { align(center)[ #here().page() ] }, 
)

#pagebreak()

#set page(numbering: "1.")

#outline(depth: 2)

#pagebreak()

= Założenia i wymagania projektowe

== Cel i koncepcja

Głównym celem projektu jest zaprojektowanie, zaprogramowanie i wdrożenie dedykowanego układu pełniącego funkcję bezprzewodowej karty sieciowej (NIC) P2P. Urządzenie opiera się na mikrokontrolerze ESP32 wykorzystującym wysokowydajny, bezpołączeniowy protokół radiowy ESP-NOW. 

Projekt stanowi alternatywę dla tradycyjnych, przewodowych sieci Ethernet oraz skomplikowanych w konfiguracji sieci WLAN, eliminując potrzebę stosowania punktów dostępowych (Access Point) czy skomplikowanych procedur uwierzytelniania. Podłączony do hosta przez interfejs USB układ ESP32 emuluje standardowe urządzenie sieciowe, realizując transmisję pakietów w oparciu o zmodyfikowane MTU.

== Wymagania sprzętowe i programowe

=== Moduły transmisyjne
Dwa moduły ESP32 wyposażone w zintegrowany układ radiowy 2.4 GHz (802.11 b/g/n) z natywnym wsparciem dla warstwy sterownika ESP-NOW.

=== Stacja robocza
Komputer klasy PC pracujący pod kontrolą systemu operacyjnego, wyposażony w interfejs USB.

=== Narzędzia programistyczne i środowisko budowania
Język C, zbudowany w oparciu o platformę `esp-idf`.

= Modelowanie i architektura systemu

System został opracowany na mikrokontrolerach Seeed Studio Xiao ESP32C3 oraz ESP32S3. Płytki dalej są nazywane odpowiednio C3 oraz S3.

W wyniku ograniczeń sprzętowych system zaimplementowany został na dwa różne sposoby. S3 posiada wbudowany system Plug & Play, ponieważ C3 nie może komunikować się bezpośrednio po USB. Stąd połączenie nawiązane przez płytkę ESP32C3 z narzędzia `slattach` (część pakietu `net-tools` systemu Linuks).

== Architektura warstwowa komunikacji

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#figure(
  caption: [Schemat komunikacji radiowej],
  
diagram(
  node-stroke: 0.5pt,
  node-corner-radius: 4pt,
  spacing: 25mm, // Zwiększony odstęp poziomy dla czytelności podpisu

  // Węzły
  node((0, 0), [*PC 1*], fill: blue.lighten(90%)),
  node((1, 0), [*ESP32-C3*], fill: orange.lighten(90%)),
  node((2, 0), [*ESP32-S3*], fill: orange.lighten(90%)),
  node((3, 0), [*PC 2*], fill: blue.lighten(90%)),

  // Połączenia
  edge((0, 0), (1, 0), "->"),
  edge((1, 0), (2, 0), "<=>", [kanał radiowy]),
  edge((3, 0), (2, 0), "->"),
)
)

== Ograniczenia sprzętowe

C3 względem S3 nie ma USB OTG, który znajduje się w mikrokontrolerze S3. Ponieważ C3 nie posiada wyżej wymienionego mechanizmu, utrudnia to trochę sprawę z punktu widzenia projektu. Układ znajdujący się w C3 posiada tylko USB Serial/JTAG, co wymusza podwójną implementację projektu pod dwie różne architektury.

== Obudowa

Na potrzeby tego projektu nie została przygotowana żadna specjalistyczna obudowa, przez to że system składa się z dwóch osobnych płytek mogą zostać wykorzystane dostępne już w społeczności projekty. Przykładem takiego projektu jest `ESP32-C3 case` autorstwa `@jacek` (https://www.printables.com/model/162815-esp32-c3-case).

#figure(
  caption: [Przykładowa obudowa dla ESP32-C3],
  kind: "pic",
  supplement: "Zdjęcie", 
  image("esp32case.webp")
)

= Problematyka projektowa

== Internet Protocol v4

Internet Protocol version 4 (IPv4) to protokół warstwy sieciowej (warstwa 3 modelu OSI), odpowiadający za logiczne adresowanie urządzeń (32-bitowe adresy) oraz wyznaczanie tras dla pakietów danych w sieciach komputerowych. Działa bezpołączeniowo i nie gwarantuje dostarczenia danych (tzw. best-effort delivery), kontrolą błędów i retransmisją pakietów zajmują się warstwy wyższe (np. TCP).

Jednostką danych jest pakiet, określany potocznie ramką IP, ma standardowo 20 bajtów (13 obowiązkowych pól i jedno nieobowiązkowe) nagłówka.

== ESP-NOW

ESP-NOW to bezpołączeniowy protokół komunikacji bezprzewodowej opracowany przez firmę Espressif (dla układów ESP8266 i ESP32). Umożliwia bezpośrednią wymianę krótkich komunikatów między urządzeniami po adresach MAC z pominięciem pełnego stosu TCP/IP, routera Wi-Fi i procedury nawiązywania połączenia. Dzięki czemu zapewnia minimalne opóźnienia i bardzo niskie zużycie energii.

Na poziomie radiowym ESP-NOW wykorzystuje standardową ramkę zarządzającą IEEE 802.11 typu Vendor-Specific Action Frame, w której właściwe dane zajmują maksymalnie 1470 bajtów (250 bajtów dla wersji v1.0; 1470 dla wersji v2.0).

W przypadku włączenia szyfrowania (algorytm CCMP z kluczami PMK i LMK) część ramki z danymi zostaje dodatkowo zabezpieczona przed podsłuchem i modyfikacją, a odbiorca na poziomie warstwy łącza automatycznie odsyła sprzętowe potwierdzenie odbioru (ACK).

=== Ewolucja standardu ESP-NOW v2.0

W nowszych wydaniach środowiska `esp-idf` (od wersji v5.0 wzwyż) protokół ESP-NOW doczekał się rewizji v2.0, która rozszerza maksymalny rozmiar ładunku użytecznego pojedynczej ramki z dotychczasowych 250 bajtów (v1.0) do 1470 bajtów. Teoretycznie wartość ta pozwala na przesyłanie pełnych pakietów IPv4 (przy MTU 1400 B) w pojedynczej ramce radiowej 802.11 typu _Vendor-Specific Action Frame_, całkowicie eliminując konieczność programowej fragmentacji i reasemblacji w warstwie łącza danych.

W niniejszym projekcie celowo zdecydowano się jednak na implementację własnego mechanizmu fragmentacji opartego na limicie wersji v1.0 (244 B ładunku + 6 B nagłówka `frag_hdr_t`), co wynika z trzech głównych wariantów:
+ Kompatybilność wsteczna i heterogeniczność sprzętowa, format ramki v1.0 jest natywnie obsługiwany przez wszystkie rewizje układów z rodziny ESP (w tym starsze jednostki ESP8266 oraz wczesne wersje SDK), co pozwala na włączenie do sieci węzłów starszej generacji bez modyfikacji protokołu transportowego.
+ Odporność na zakłócenia w kanale bez korekcji FEC, przy braku selektywnej retransmisji podbloków w warstwie fizycznej 802.11b/g, prawdopodobieństwo uszkodzenia pojedynczego bitu (BER) w długiej ramce o rozmiarze 1470 B w zaszumionym paśmie ISM 2,4 GHz jest wyższe niż dla krótkiej ramki 250-bajtowej. Zastosowanie mniejszych jednostek PDU pozwala na zbadanie zachowania mechanizmów reasemblacji w warunkach rzeczywistych zakłóceń.
+ Weryfikacja architektury wieloslotowej, własna warstwa fragmentacji umożliwiła praktyczną analizę problemów synchronizacji, wywłaszczania buforów oraz ataków na proces składania pakietów, które są kluczowe z punktu widzenia bezpieczeństwa systemów IoT.

Istotnym aspektem warstwy fizycznej w domyślnej konfiguracji ESP-NOW jest także sztywne ustawienie prędkości modulacji na poziomie podstawowym 1 Mbit/s (standard 802.11b z modulacją DSSS/DBPSK). Zapewnia to wprawdzie maksymalny budżet łącza i wysoką czułość odbiornika, ale wprowadza znaczący stały narzut czasowy na każdą transakcję radiową (długa preambuła PLCP trwająca $192\ \mu"s"$ oraz czas oczekiwania na ramki ACK). 

Środowisko `esp-idf` umożliwia zmianę tego zachowania w dwóch przeciwstawnych kierunkach za pomocą funkcji `esp_wifi_config_espnow_rate()`:
- Zwiększenie przepustowości (tryby 802.11g/n), wymuszenie modulacji OFDM (np. `WIFI_PHY_RATE_18M` lub `WIFI_PHY_RATE_54M`) skraca czas emisji pojedynczego fragmentu w eterze kilkukrotnie, redukując problem wąskiego gardła liczby pakietów na sekundę kosztem zmniejszenia zasięgu skutecznego.
- Maksymalizacja zasięgu, własnościowa modulacja firmy Espressif obniżająca przepływność fizyczną do 512 kbit/s lub 256 kbit/s, ale poprawiająca czułość odbiornika o ok. 4--6 dB, co pozwala na zestawienie łącza P2P w trudnych warunkach terenowych na dystansie przekraczającym 1 km w linii wzroku.

== Sterownik karty sieciowej

Poniższy opis skupia się na implementacji dotyczącej węzła S3, który udostępnia hostowi interfejs sieciowy z adresem IP `10.0.0.1` bez ingerencji użytkownika (Plug & Play). Wspólna logika radiowa (inicjalizacja Wi-Fi/ESP-NOW, fragmentacja, reasemblacja, kolejka nadawcza oraz mechanizm autodiscovery) została wydzielona do współdzielonego komponentu `espnow_common`.

=== Nadawanie w S3

Proces przebiega w dwóch głównych etapach:

1. Wstępna obróbka ramki (`usb_ncm_recv_cb`)

Komputer przez interfejs USB-NCM wysyła pełne ramki Ethernet (14 bajtów nagłówka L2 + ładunek L3). Mikrokontroler filtruje i przechwytuje lokalnie ruch niezbędny do działania karty sieciowej (bez wysyłania go w eter):
- ARP (`0x0806`) -- odpowiada jako Proxy ARP, podając wirtualny adres MAC (`02:00:00:00:00:02`) dla IP peera `10.0.0.2`.
- DHCP (UDP port 67) -- przydziela komputerowi adres `10.0.0.1` oraz bramę `10.0.0.2`.

2. Kolejkowanie, fragmentacja i wysyłka (`espnow_tx_task`)

Jeśli ramka zawiera pakiet IPv4 (`0x0800`), kod odrzuca 14 bajtów nagłówka Ethernet i umieszcza czysty pakiet IPv4 w kolejce `espnow_tx_q`. Zadanie `espnow_tx_task` pobiera pakiet, rozwiązuje docelowy adres MAC na podstawie tabeli peerów (`espnow_resolve_dest_mac`) i dzieli dane na fragmenty po maksymalnie 244 bajty. Do każdej części doklejany jest 6-bajtowy nagłówek fragmentacji (`frag_hdr_t`), dając maksymalnie 250 B (limit ładunku ESP-NOW). Kontrola przepływu odbywa się poprzez oczekiwanie na semafor `espnow_tx_sem` sygnalizowany przez callback `on_espnow_send`.

=== Odbieranie w S3
1. Walidacja i wieloslotowa reasemblacja (`espnow_reasm_process_src`)

- Program weryfikuje strukturę nagłówka i poprawność indeksów (maksymalnie 7 fragmentów, `MAX_PACKET_SIZE = 1600` B).
- Reasemblacja wykorzystuje 8 niezależnych slotów (`REASM_SLOTS = 8`) indeksowanych parą `(src_mac, frame_id)`, co pozwala na równoległe składanie ramek od różnych nadawców bez wzajemnego nadpisywania bufora.

2. Defragmentacja

Każdy fragment jest kopiowany do bufora wyjściowego `pkt_item_t` z przesunięciem 14 bajtów (zarezerwowane miejsce na nagłówek Ethernet). Odebranie fragmentu oznaczane jest bitem w masce `mask`, co pozwala na dotarcie fragmentów w dowolnej kolejności.

3. Przekazanie do hosta (`usb_tx_task`)

Po skompletowaniu wszystkich fragmentów na początku bufora uzupełniany jest nagłówek Ethernet (`Dst MAC = host_mac`, `Src MAC = remote_mac`, `EtherType = 0x0800`), a gotowa ramka trafia przez kolejkę `usb_tx_q` i funkcję `tinyusb_net_send_sync` do stosu sieciowego systemu operacyjnego.

=== Komunikacja z C3 i wykrywanie węzłów (Autodiscovery)

Obie wersje programu korzystają ze wspólnego komponentu `espnow_common` i realizują identyczną komunikację radiową wraz z automatycznym wykrywaniem węzłów (`espnow_discovery_task` rozgłaszający ramki `BEACON`/`RESPONSE` z sygnaturą `NICD` i utrzymujący tabelę do 16 peerów). Jedyna różnica leży w warstwie 2 (łącza danych) pomiędzy mikrokontrolerem a PC: ESP32-C3 zamiast USB-NCM wykorzystuje protokół SLIP (RFC 1055) na interfejsie `USB-Serial/JTAG`, gdzie ramki oddzielane są bajtem `SLIP_END` (`0xC0`), a wystąpienia `0xC0` i `0xDB` kodowane są sekwencjami z `SLIP_ESC` (`0xDB`).
= Projekt warstwy programowej

Projekt ten nie wymaga tworzenia specjalistycznego układu przez co zapewnia dużo większą użyteczność w ograniczonych warunkach. Wystarczy podłączyć zaprogramowane mikrokontrolery do urządzeń końcowych i można OOTB korzystać z projektu. Wyjątkiem jest C3 który trzeba skonfigurować zgodnie z konfiguracją lub użyć skryptu np. `setup_c3.sh`.

== Implementacja węzła C3 (SLIP)

=== Przegląd architektury i model współbieżności

Węzeł oparty na mikrokontrolerze ESP32-C3 realizuje dwukierunkowy most warstwy łącza danych pomiędzy interfejsem szeregowym hosta (`USB-Serial/JTAG`) a bezprzewodowym interfejsem radiowym ESP-NOW. Host komunikuje się z mikrokontrolerem za pośrednictwem protokołu SLIP (RFC 1055), mapowanego w systemie operacyjnym jako interfejs `sl0`.

Architektura oprogramowania opiera się na separacji zadań w środowisku FreeRTOS oraz mechanizmie kolejki:
- `slip_rx_task` (priorytet 5, stos 8192 B) -- pobiera ciągły strumień bajtów z bufora pierścieniowego `USB-Serial/JTAG`, dekoduje ramki SLIP i bezpośrednio wywołuje fragmentację pakietu IPv4 do ramek ESP-NOW.
- `on_espnow_recv` (kontekst zdarzeń sterownika Wi-Fi) -- weryfikuje nagłówki fragmentów radiowych, realizuje reasemblację pakietu IPv4 w buforze statycznym i przekazuje gotowy pakiet nieblokująco do kolejki `slip_tx_q`.
- `slip_tx_q` (kolejka FreeRTOS o pojemności 8 elementów typu `pkt_item_t`) -- buforuje zreasemblowane pakiety IPv4 pomiędzy kontekstem radiowym a wątkiem nadawczym USB.
- `slip_tx_task` (priorytet 5, stos 4096 B) -- pobiera pakiety z kolejki `slip_tx_q`, dokonuje enkapsulacji SLIP i przekazuje gotowy strumień do kontrolera `USB-Serial/JTAG`.

#figure(
  diagram(
    node-stroke: 0.7pt + rgb("#2b579a"),
    edge-stroke: 0.7pt + luma(60),
    spacing: (28mm, 9mm),

    // Warstwa hosta i interfejsu szeregowego
    node((0.5, 0), [*Host PC (Linuks)* \ Interfejs sieciowy `sl0`], fill: rgb("#eef4fb"), corner-radius: 4pt, inset: 6pt, width: 52mm),
    node((0.5, 1), [*USB-Serial/JTAG*\ Bufory pierścieniowe RX/TX (4 KB)], fill: rgb("#f4f4f4"), corner-radius: 4pt, inset: 6pt, width: 52mm),
    
    // Ścieżka TX (Host -> ESP-NOW) po lewej (x = 0)
    node((0, 2), [`slip_rx_task` \ Dekodowanie SLIP], fill: rgb("#fff8e7"), corner-radius: 4pt, inset: 5pt, width: 44mm),
    node((0, 3), [`espnow_send_ip_packet` \ Fragmentacja (bloki 244 B)], fill: rgb("#fff8e7"), corner-radius: 4pt, inset: 5pt, width: 44mm),

    // Ścieżka RX (ESP-NOW -> Host) po prawej (x = 1)
    node((1, 2), [`slip_tx_task` \ Enkapsulacja SLIP], fill: rgb("#e9f7ef"), corner-radius: 4pt, inset: 5pt, width: 44mm),
    node((1, 2.5), [`slip_tx_q` \ Kolejka FreeRTOS (8 elem.)], shape: "rect", fill: rgb("#d4efdf"), inset: 4pt, width: 44mm),
    node((1, 3), [`on_espnow_recv` \ Reasemblacja (Wi-Fi CB)], fill: rgb("#e9f7ef"), corner-radius: 4pt, inset: 5pt, width: 44mm),

    // Warstwa radiowa
    node((0.5, 4), [*Radio Wi-Fi (Kanał 1)* \ ESP-NOW Broadcast `FF:FF:FF:FF:FF:FF`], fill: rgb("#fdedec"), stroke: 0.7pt + rgb("#c0392b"), corner-radius: 4pt, inset: 6pt, width: 58mm),

    // Krawędzie USB
    edge((0.5, 0), (0.5, 1), "<->", label: [USB]),
    
    // Krawędzie TX (w dół po lewej)
    edge((0.5, 1), (0, 2), "->", label: [Strumień], label-side: left),
    edge((0, 2), (0, 3), "->", label: [Pakiet IPv4]),
    edge((0, 3), (0.5, 4), "->", label: [Fragmenty], label-side: left),

    // Krawędzie RX (w górę po prawej)
    edge((0.5, 4), (1, 3), "->", label: [Fragmenty], label-side: right),
    edge((1, 3), (1, 2.5), "->"),
    edge((1, 2.5), (1, 2), "->"),
    edge((1, 2), (0.5, 1), "->", label: [Ramka SLIP], label-side: right),
  ),
  caption: [Architektura przepływu danych oraz podział zadań FreeRTOS w module ESP32-C3.]
)


=== Struktury danych i protokół fragmentacji

Maksymalny rozmiar ładunku ramki ESP-NOW v1 wynosi 250 bajtów. Aby przesłać pakiety IPv4 o standardowym MTU 1500 bajtów (`MAX_PACKET_SIZE`), zaimplementowano warstwę fragmentacji opartą na 6-bajtowym nagłówku `frag_hdr_t` oraz strukturze transportowej `espnow_frag_pkt_t` z atrybutem upakowania (`__attribute__((packed))`):

#table(
  columns: (auto, auto, auto, 1fr),
  inset: 7pt,
  align: (left, left, center, left),
  fill: (_, row) => if row == 0 { rgb("#2b579a") } else if calc.odd(row) { luma(248) } else { white },
  table.header(
    text(fill: white, weight: "bold")[Pole],
    text(fill: white, weight: "bold")[Typ],
    text(fill: white, weight: "bold")[Rozmiar],
    text(fill: white, weight: "bold")[Funkcja w protokole]
  ),
  [`frame_id`], [`uint16_t`], [2 B], [Identyfikator pakietu IPv4 (inkrementowany atomowo).],
  [`frag_idx`], [`uint8_t`], [1 B], [Indeks fragmentu (od `0` do `frag_total - 1`).],
  [`frag_total`], [`uint8_t`], [1 B], [Całkowita liczba fragmentów pakietu (maksymalnie 7).],
  [`payload_len`], [`uint16_t`], [2 B], [Długość użytecznego ładunku w polu `data` (maks. 244 B).],
  [`data[244]`], [`uint8_t[]`], [0--244 B], [Wycinek transmitowanego pakietu IPv4.],
)

Do buforowania kompletnych jednostek PDU w kolejce `slip_tx_q` zdefiniowano strukturę `pkt_item_t` zawierającą 16-bitowe pole długości `len` oraz tablicę `data` o rozmiarze 1500 bajtów. Transmisja radiowa odbywa się bezpołączeniowo na adres rozgłoszeniowy `peer_mac` (`FF:FF:FF:FF:FF:FF`).

=== Ścieżka nadawcza: Host $arrow.r$ ESP-NOW

Ścieżka nadawcza konwertuje asynchroniczny strumień SLIP na sfragmentowane ramki radiowe:
1. *Odbiór i dekapsulacja SLIP:* Zadanie `slip_rx_task` odczytuje bloki do 256 bajtów z bufora `USB-Serial/JTAG` z limitem oczekiwania 20 ms. Dekoder przetwarza bajty w maszynie stanów:
   - Bajt `SLIP_END` (`0xC0`) oznacza granicę pakietu -- jeśli w buforze `ip_buf` zebrano dane (`pos > 0`), następuje przekazanie do wysyłki radiowej.
   - Bajt `SLIP_ESC` (`0xDB`) ustawia flagę ucieczki `escaped`.
   - Sekwencje `SLIP_ESC + SLIP_ESC_END` (`0xDB 0xDC`) oraz `SLIP_ESC + SLIP_ESC_ESC` (`0xDB 0xDD`) mapowane są odpowiednio na wartości `0xC0` i `0xDB`.
2. *Fragmentacja pakietu IPv4 (`espnow_send_ip_packet`):*
   - Wyznaczana jest liczba fragmentów: $N = floor((L + 243) / 244)$. Dla $L = 1500$ B wynosi ona 7.
   - Atomowo generowany jest numer identyfikacyjny: `__atomic_fetch_add(&tx_frame_id, 1, __ATOMIC_RELAXED)`.
   - W pętli tworzone są ramki `espnow_frag_pkt_t` z wycinkami ładunku po maksymalnie 244 bajty.
3. *Kontrola przepływu radiowego:* W przypadku przepełnienia wewnętrznego bufora sterownika Wi-Fi (`ESP_ERR_ESPNOW_NO_MEM`), procedura ponawia wysyłkę do 20 razy w odstępach 1 ms. Między kolejnymi fragmentami wprowadzana jest stała pauza `esp_rom_delay_us(400)` zapobiegająca przeciążeniu kolejki TX radia.

=== Ścieżka odbiorcza: ESP-NOW $arrow.r$ Host

Ścieżka odbiorcza rekonstruuje pakiety z odebranych fragmentów i transmituje je strumieniowo do hosta:
1. *Walidacja nagłówka:* Callback `on_espnow_recv` odrzuca ramki o długości mniejszej niż 6 bajtów, fragmenty o indeksie `frag_idx >= 7`, pakiety o deklarowanej liczbie fragmentów `frag_total > 7` oraz ładunki `payload_len > 244`.
2. *Zarządzanie stanem reasemblacji:* Globalna zmienna `rx_fid` przechowuje ID aktualnie składanego pakietu. Pojawienie się innego identyfikatora unieważnia dotychczasowy stan (`rx_mask = 0`, `rx_total_len = 0`).
3. *Maska bitowa i zapis do bufora:* Fragment kopiowany jest pod offset `frag_idx * 244` w tablicy `rx_buf`. Fakt odebrania fragmentu odnotowywany jest bitem w masce: `rx_mask |= (1U << frag_idx)`. Gdy odebrany zostanie ostatni fragment (`frag_idx == frag_total - 1`), rejestrowana jest całkowita długość pakietu `rx_total_len`.
4. *Weryfikacja kompletności:* Gdy maska osiągnie wartość docelową:
   $ "expected_mask" = (1 "U" lt.double "frag_total") - 1 $
   pakiet kopiowany jest do struktury `pkt_item_t` i wstawiany nieblokująco do kolejki `slip_tx_q`.
5. *Enkapsulacja i wysyłka do hosta:* Zadanie `slip_tx_task` pobiera pakiet z kolejki i koduje go zgodnie ze standardem SLIP:
   - Transmisję rozpoczyna i kończy znacznik `SLIP_END` (`0xC0`), co ułatwia synchronizację odbiornika hosta i odrzucenie szumów linii.
   - Bajty `0xC0` i `0xDB` w treści zastępowane są dwubajtowymi sekwencjami ucieczki.
   - Zakodowany bufor (maks. 3002 B) jest synchronicznie zapisywany funkcją `usb_serial_jtag_write_bytes` z limitem czasu 50 ms.

=== Inicjalizacja i konfiguracja podsystemów

Funkcja startowa `app_main` konfiguruje komponenty w następującej sekwencji:
1. *Pamięć NVS:* Inicjalizacja poprzez `nvs_flash_init` z obsługą wymazania partycji (`nvs_flash_erase`) w razie braku wolnych stron lub zmiany formatu.
2. *Sterownik USB-Serial/JTAG:* Konfiguracja sprzętowego interfejsu z buforami pierścieniowymi RX i TX o pojemności 4096 B każdy.
3. *Podsystem Wi-Fi:* Inicjalizacja stosu `esp_netif`, domyślnej pętli zdarzeń oraz sterownika Wi-Fi w trybie stacji (`WIFI_MODE_STA`) z parametrem `WIFI_STORAGE_RAM` i wymuszeniem kanału radiowego 1.
4. *Warstwa ESP-NOW:* Inicjalizacja protokołu, rejestracja callbacku `on_espnow_recv` oraz rejestracja nieszyfrowanego węzła `peer_mac` (`FF:FF:FF:FF:FF:FF`) na kanale 1.
5. *Współbieżność FreeRTOS:* Utworzenie 8-elementowej kolejki `slip_tx_q` oraz zadań `slip_tx` (priorytet 5, stos 4 KB) i `slip_rx` (priorytet 5, stos 8 KB).

== Implementacja węzła S3 (NCM)

=== Przegląd architektury i model współbieżności

Węzeł oparty na mikrokontrolerze ESP32-S3 wykorzystuje wbudowany kontroler USB OTG, emulując standardową kartę sieciową USB w klasie CDC-NCM (*Network Control Model*). Urządzenie działa w trybie Plug & Play -- nie wymaga konfiguracji oprogramowania po stronie systemu operacyjnego hosta, udostępniając wirtualną kartę sieciową z adresacją `10.0.0.1/24`.

W celu uniknięcia blokowania i zakleszczeń (*deadlocks*) w kontekście przerwań stosu TinyUSB, architektura rozdziela ścieżki przetwarzania na dedykowane kolejki i zadania FreeRTOS:
- `usb_ncm_recv_cb` (callback TinyUSB) -- wykonuje szybką filtrację i klasyfikację przychodzących z USB ramek Ethernet (ARP, DHCP, IPv4).
- `usb_tx_q` (kolejka FreeRTOS o pojemności 8 elementów `pkt_item_t`) -- buforuje ramki Ethernet kierowane do hosta PC (odpowiedzi Proxy ARP, komunikaty DHCP oraz zreasemblowany ruch IPv4).
- `usb_tx_task` (priorytet 5, stos 4096 B) -- pobiera ramki z `usb_tx_q` i przekazuje je do hosta przez wywołanie `tinyusb_net_send_sync`.
- `espnow_tx_q` (kolejka FreeRTOS o pojemności 8 elementów `pkt_item_t`) -- buforuje pakiety IPv4 przeznaczone do emisji radiowej.
- `espnow_tx_task` (priorytet 5, stos 4096 B) -- pobiera pakiety z `espnow_tx_q`, dzieli je na fragmenty i transmituje przez ESP-NOW.
- `on_espnow_recv` (kontekst zdarzeń Wi-Fi) -- odpowiada za walidację fragmentów radiowych, rekonstrukcję nagłówka Ethernet L2 i wstawienie ramki do `usb_tx_q`.

#figure(
  diagram(
    node-stroke: 0.7pt + rgb("#2b579a"),
    edge-stroke: 0.7pt + luma(60),
    spacing: (28mm, 9mm),

    // Warstwa hosta i TinyUSB
    node((0.5, 0), [*Host PC*\ Interfejs sieciowy CDC-NCM (`10.0.0.1`)], fill: rgb("#e3f2fd"), corner-radius: 4pt, inset: 6pt, width: 56mm),
    node((0.5, 1), [*TinyUSB NCM Stack*\ Callback odbiorczy `usb_ncm_recv_cb`], fill: rgb("#fff3e0"), corner-radius: 4pt, inset: 6pt, width: 56mm),

    // Ścieżka TX (Host -> ESP-NOW) po lewej (x = 0)
    node((0, 2), [*Kolejka `espnow_tx_q`*\ Buforowanie IPv4 (8 elem.)], shape: "rect", fill: rgb("#e8f5e9"), inset: 4pt, width: 44mm),
    node((0, 3), [`espnow_tx_task` \ Fragmentacja (bloki 244 B)], fill: rgb("#e8f5e9"), corner-radius: 4pt, inset: 5pt, width: 44mm),

    // Ścieżka RX (ESP-NOW -> Host) po prawej (x = 1)
    node((1, 1.8), [`usb_tx_task` \ Nadawanie `tinyusb_net_send_sync`], fill: rgb("#e3f2fd"), corner-radius: 4pt, inset: 5pt, width: 44mm),
    node((1, 2.4), [*Kolejka `usb_tx_q`*\ Bufor ramek Ethernet (8 elem.)], shape: "rect", fill: rgb("#bbdefb"), inset: 4pt, width: 44mm),
    node((1, 3.2), [`on_espnow_recv` \ Reasemblacja IPv4 + Nagłówek Eth], fill: rgb("#ffebee"), corner-radius: 4pt, inset: 5pt, width: 44mm),

    // Warstwa radiowa
    node((0.5, 4), [*Radio Wi-Fi (Kanał 1)* \ ESP-NOW Broadcast `FF:FF:FF:FF:FF:FF`], fill: rgb("#fdedec"), stroke: 0.7pt + rgb("#c0392b"), corner-radius: 4pt, inset: 6pt, width: 58mm),

    // Krawędzie host <-> TinyUSB
    edge((0.5, 0), (0.5, 1), "<->", label: [USB NCM]),

    // Ścieżka TX: TinyUSB -> espnow_tx_q -> espnow_tx_task -> Radio
    edge((0.5, 1), (0, 2), "->", label: [IPv4 (odcięty Eth)], label-side: left),
    edge((0, 2), (0, 3), "->"),
    edge((0, 3), (0.5, 4), "->", label: [Fragmenty], label-side: left),

    // Emulacja lokalna: TinyUSB -> usb_tx_q (ARP Reply / DHCP Offer/Ack)
    edge((0.5, 1), (1, 2.4), "->", label: [ARP / DHCP], label-side: right),

    // Ścieżka RX: Radio -> on_espnow_recv -> usb_tx_q -> usb_tx_task -> Host
    edge((0.5, 4), (1, 3.2), "->", label: [Fragmenty], label-side: right),
    edge((1, 3.2), (1, 2.4), "->", label: [Ramka Eth]),
    edge((1, 2.4), (1, 1.8), "->"),
    edge((1, 1.8), (0.5, 0), "->", bend: -25deg, label: [USB TX], label-side: right),
  ),
  caption: [Architektura przepływu danych oraz separacja zadań FreeRTOS w module ESP32-S3.]
)


=== Struktury danych i protokół fragmentacji

W module S3 zastosowano identyczny format jednostki transportowej ESP-NOW jak w module C3, co zapewnia pełną kompatybilność binarną łącza radiowego:
- `frag_hdr_t` (6 B, packed) -- pola `frame_id` (2 B), `frag_idx` (1 B), `frag_total` (1 B), `payload_len` (2 B).
- `espnow_frag_pkt_t` (maksymalnie 250 B, packed) -- nagłówek `frag_hdr_t` oraz bufor `data` o rozmiarze do 244 B (`MAX_FRAG_PAYLOAD`).
- `pkt_item_t` -- bufor kolejkowy o dopuszczalnej wielkości pakietu `MAX_PACKET_SIZE = 1600` B (z uwzględnieniem narzutu 14 bajtów nagłówka Ethernet).

W warstwie adresacji urządzenie operuje na trzech tożsamościach MAC:
1. `peer_mac` (`FF:FF:FF:FF:FF:FF`) -- adres rozgłoszeniowy dla ramek ESP-NOW.
2. `host_mac` (początkowo `02:00:00:00:00:01`) -- adres fizyczny interfejsu PC, aktualizowany dynamicznie z nagłówka każdej ramki odebranej z USB (`memcpy(host_mac, eth + 6, 6)`).
3. `remote_mac` (`02:00:00:00:00:02`) -- wirtualny adres MAC przypisany bramie domyślnej oraz zdalnemu węzłowi sieci.

=== Ścieżka nadawcza: Host $arrow.r$ ESP-NOW

Ścieżka nadawcza obejmuje dekapsulację L2/L3, obsługę usług lokalnych oraz fragmentację radiową:
1. *Klasyfikacja ruchu w `usb_ncm_recv_cb`:*
   - Z przychodzącej ramki odczytywany jest typ protokołu `EtherType` (bajty 12--13).
   - Żądania *Proxy ARP* (`EtherType == 0x0806`, operacja 1) o adres `10.0.0.2` są obsługiwane lokalnie: mikrokontroler generuje 42-bajtowy pakiet ARP Reply z adresem `remote_mac` i wstawia go do `usb_tx_q`. Zapytania o `10.0.0.1` są ignorowane w celu eliminacji fałszywych detekcji kolizji IP (*DAD*).
   - Ruch *DHCP* (`EtherType == 0x0800`, port UDP 67) kierowany jest do funkcji `handle_dhcp`, która parsuje zapytania DISCOVER/REQUEST i odsyła komunikaty OFFER/ACK przydzielające IP `10.0.0.1`, bramę `10.0.0.2` oraz maskę `255.255.255.0` (z obliczeniem sumy kontrolnej IP przez `ip_chksum`). Odpowiedź trafia do `usb_tx_q`.
   - Ruch docelowy *IPv4* (`EtherType == 0x0800`): odcinany jest 14-bajtowy nagłówek Ethernet (`eth + 14`), a sam ładunek IPv4 umieszczany jest w kolejce `espnow_tx_q`.
2. *Fragmentacja i wysyłka w `espnow_tx_task`:*
   - Zadanie pobiera pakiet z `espnow_tx_q` i wylicza liczbę części: $N = floor((L_"IP" + 243) / 244)$.
   - Pobiera atomowy `frame_id` z licznika `tx_frame_id`.
   - Formuje ramki `espnow_frag_pkt_t` i wywołuje `esp_now_send`.
3. *Kontrola przepływu radiowego:* Identycznie jak w module C3, przy błędzie braku pamięci (`ESP_ERR_ESPNOW_NO_MEM`) następuje do 20 ponowień z opóźnieniem 1 ms, a po każdej wysłanej ramce następuje pauza sprzętowa `esp_rom_delay_us(400)`.

=== Ścieżka odbiorcza: ESP-NOW $arrow.r$ Host

Ścieżka odbiorcza rekonstruuje pakiet IPv4, hermetyzuje go w pełną ramkę Ethernet i przekazuje do hosta przez interfejs NCM:
1. *Walidacja i synchronizacja:* Callback `on_espnow_recv` weryfikuje poprawność indeksów fragmentu (`frag_idx < 7`, `frag_total <= 7`, `payload_len <= 244`). Zmiana `frame_id` resetuje stan składania (`rx_mask = 0`, `rx_total_len = 0`).
2. *Składanie ładunku z offsetem L2:* Dane fragmentu kopiowane są bezpośrednio do globalnego bufora `rx_usb_pkt.data` pod offset $14 + "frag_idx" times 244$. Pierwsze 14 bajtów bufora pozostaje zarezerwowane na nagłówek Ethernet.
3. *Maska bitowa i kompletność:* Każdy fragment odnotowywany jest w masce: `rx_mask |= (1U << frag_idx)`. Po zrównaniu się maski z `(1U << frag_total) - 1`:
   - W buforze syntetyzowany jest nagłówek Ethernet: adres docelowy `host_mac`, adres źródłowy `remote_mac` oraz znacznik `EtherType = 0x0800`.
   - Długość całkowita ramki ustalana jest na `rx_total_len + 14`.
   - Ramka trafia nieblokująco do kolejki `usb_tx_q`.
4. *Transmisja do hosta (`usb_tx_task`):* Zadanie pobiera skompletowaną ramkę Ethernet z kolejki `usb_tx_q` i wywołuje funkcję `tinyusb_net_send_sync` z limitem czasu 50 ms.

=== Inicjalizacja i konfiguracja podsystemów

Funkcja `app_main` w module ESP32-S3 inicjalizuje zasoby w następującej kolejności:
1. *Pamięć NVS:* Inicjalizacja pamięci nieulotnej za pomocą `nvs_flash_init` z ewentualnym wymazaniem w przypadku niezgodności struktur.
2. *Kolejki i zadania FreeRTOS:* Utworzenie kolejek `espnow_tx_q` oraz `usb_tx_q` (pojemność po 8 elementów) oraz uruchomienie zadań `espnow_tx_task` i `usb_tx_task` z priorytetem 5 (stos po 4 KB).
3. *Sterownik TinyUSB NCM:* Instalacja sterownika bazowego TinyUSB oraz konfiguracja interfejsu sieciowego NCM (`tinyusb_net_init`) z adresem sprzętowym MAC `02:00:00:00:00:01` i rejestracją callbacku `usb_ncm_recv_cb`.
4. *Podsystem Wi-Fi:* Konfiguracja stosu sieciowego `esp_netif`, uruchomienie pętli zdarzeń, start modułu Wi-Fi w trybie `WIFI_MODE_STA` z pamięcią `WIFI_STORAGE_RAM` oraz blokadą kanału na wartości 1.
5. *Warstwa ESP-NOW:* Inicjalizacja `esp_now_init`, rejestracja procedury zwrotnej odbiornika `on_espnow_recv` i zarejestrowanie węzła rozgłoszeniowego `FF:FF:FF:FF:FF:FF` bez szyfrowania.

=== Ograniczenia i właściwości protokołu

Projekt obu węzłów cechują wspólne właściwości wynikające ze specyfiki ESP-NOW:
- *Brak sprzętowych retransmisji:* Użycie adresu rozgłoszeniowego `FF:FF:FF:FF:FF:FF` eliminuje mechanizm potwierdzeń ACK warstwy MAC 802.11. Utrata pojedynczego fragmentu skutkuje odrzuceniem całego pakietu IP -- integralność sesji opiera się na protokołach warstw wyższych (np. TCP).
- *Pojedynczy bufor reasemblacji:* Moduły posiadają pojedynczy kontekst składania ramek. Przeplot fragmentów od różnych nadawców skutkuje resetem stanu i utratą pakietu.
- *Asymetria warstwy fizycznej:* Moduł S3 realizuje bezobsługowe połączenie Plug & Play dzięki emulacji CDC-NCM, DHCP i Proxy ARP, natomiast moduł C3 wymaga zestawienia tunelu programowego po stronie hosta (narzędzie `slattach`).

= Uruchomienie i testy funkcjonalne

== Testy stabilności łącza P2P
Weryfikacja ciągłości przesyłania danych pod obciążeniem generowanym narzędziem `iperf3` uruchomionym na stacji roboczej hosta. Poniższa analiza została przeprowadzona korzystając z podejścia czarnej skrzynki. Testujemy zachowanie i stabilność stworzonej karty sieciowej jakbyśmy nie wiedzieli nic o systemie.

#import "@preview/cetz:0.5.3"
#import "@preview/cetz-plot:0.1.4": plot, chart

// Parsowanie 01_ping_baseline.txt
#let ping_raw = read("01_ping_baseline.txt")
#let ping_pts = ()
#for line in ping_raw.split("\n") {
  let m = line.match(regex("icmp_seq=(\d+).*time=([0-9.]+)"))
  if m != none {
    ping_pts.push((int(m.captures.at(0)), float(m.captures.at(1))))
  }
}

// Parsowanie 04_tcp_raw.json
#let tcp_json = json("04_tcp_raw.json")
#let tcp_rtt_pts = ()
#let tcp_cwnd_pts = ()
#let tcp_bps_pts = ()

#for iv in tcp_json.intervals {
  let s = iv.streams.at(0)
  let t = s.end
  tcp_rtt_pts.push((t, s.rtt / 1000.0)) // konwersja us -> ms
  tcp_cwnd_pts.push((t, s.snd_cwnd / 1024.0)) // konwersja B -> KiB
  tcp_bps_pts.push((t, s.bits_per_second / 1000.0)) // konwersja bps -> kbps
}

// Parsowanie 03_udp_packetsize.txt (podsumowania sender / receiver)
#let udp_ps_raw = read("03_udp_packetsize.txt")
#let parse_iperf_kbps(line) = {
  let m = line.match(regex("([0-9.]+)\s+([KMG]?bits/sec)"))
  if m != none {
    let val = float(m.captures.at(0))
    let unit = m.captures.at(1)
    if unit == "Mbits/sec" { val * 1000.0 }
    else if unit == "bits/sec" { val / 1000.0 }
    else { val }
  } else { 0.0 }
}

#let ps_blocks = udp_ps_raw.split("=== TEST ROZMIAR:").slice(1)
#let udp_ps_data = ()
#for blk in ps_blocks {
  let lines = blk.split("\n")
  let size_label = lines.at(0).replace("===", "").trim()
  let snd = 0.0
  let rcv = 0.0
  for l in lines {
    if l.contains("sender") { snd = parse_iperf_kbps(l) }
    else if l.contains("receiver") and l.contains("[  4]") { rcv = parse_iperf_kbps(l) }
  }
  udp_ps_data.push((size_label, snd, rcv))
}

=== Opis środowiska testowego

Badane połączenie punkt-punkt pomiędzy hostami `10.0.0.1` (`reginleif-rp`) a `10.0.0.2` (`warrover-rp`) charakteryzuje się asymetrią warstwy łącza danych. Nadawca korzysta z interfejsu Ethernet over USB (`cdc_ncm`, MTU 1500 B), natomiast odbiorca używa interfejsu szeregowego SLIP (`sl0`, sterownik `cdc_acm`, MTU 1400 B).

#v(0.8em)
#align(center)[
  #diagram(
    node-stroke: 0.8pt + blue.darken(40%),
    node-fill: blue.lighten(95%),
    spacing: (1.8cm, 1.2cm),
    edge-stroke: 0.8pt,

    node((0,0), [*Nadawca (Sender)*\ `reginleif-rp`\ IP: `10.0.0.1`], corner-radius: 5pt, width: 3.5cm),
    edge((0,0), (1,0), "<->", label: [USB 12M\ `cdc_ncm`]),
    node((1,0), [*`enp4s0f3u2`*\ MTU: 1500 B\ `qlen 1000`], corner-radius: 4pt, fill: orange.lighten(90%), stroke: orange.darken(30%)),
    edge((1,0), (2,0), "->", label: [Medium pośrednie\ (Limit PPS / Bufory)], stroke: (dash: "dashed", paint: red.darken(20%))),
    node((2,0), [*`sl0` (SLIP)*\ MTU: 1400 B\ `qlen 500`], corner-radius: 4pt, fill: orange.lighten(90%), stroke: orange.darken(30%)),
    edge((2,0), (3,0), "<->", label: [USB 12M\ `cdc_acm`]),
    node((3,0), [*Odbiorca (Receiver)*\ `warrover-rp`\ IP: `10.0.0.2`], corner-radius: 5pt, width: 3.5cm),
  )
  #v(0.2em)
  #text(size: 9pt, style: "italic")[Rys. 1: Schemat architektury badanego łącza (na podstawie `05_env_sender.txt` i `05_env_receiver.txt`).]
]

=== Analiza testu bazowego ICMP (`01_ping_baseline.txt`)

Wykres poniżej prezentuje czas odpowiedzi RTT w funkcji numeru sekwencyjnego `icmp_seq`, wygenerowany bezpośrednio z pliku `01_ping_baseline.txt`. Widoczna jest stabilna praca w okolicach `7.0 ms` oraz nagła utrata 6 kolejnych pakietów (`icmp_seq` od 70 do 75 – ok. 1,2 s zamrożenia łącza).

#v(0.5em)
#align(center)[
  #cetz.canvas({
    plot.plot(
      size: (14, 4.8),
      x-label: [Numer sekwencyjny pakietu (`icmp_seq`)],
      y-label: [RTT (ms)],
      x-min: 0, x-max: 100,
      y-min: 5, y-max: 13,
      y-grid: "major",
      x-grid: "major",
      legend: "inner-north-east",
      {
        // Zaznaczenie strefy utraty pakietów (seq 70-75)
        plot.add-vline(70, style: (stroke: (paint: red, dash: "dashed", thickness: 0.8pt)))
        plot.add-vline(75, style: (stroke: (paint: red, dash: "dashed", thickness: 0.8pt)))
        plot.add(
          ping_pts,
          style: (stroke: 1.1pt + blue.darken(20%)),
          label: [Czas odpowiedzi ICMP RTT],
        )
      }
    )
  })
  #v(0.2em)
  #text(size: 9pt, style: "italic")[Rys. 2: Przebieg opóźnienia ICMP RTT z zaznaczonym oknem utraty pakietów (`seq 70–75`).]
]

=== Analiza przepustowości UDP (`02_udp_sweep.txt` i `03_udp_packetsize.txt`)

Testy UDP przy stałym rozmiarze pakietu 400 B (`02_udp_sweep.txt`) wykazały zamrażanie gniazda nadawczego po 1–2 sekundach dla większości prędkości powyżej `100K`. Z kolei badanie wpływu rozmiaru datagramu przy stałym strumieniu `500K` (`03_udp_packetsize.txt`) dowodzi, że wąskim gardłem jest liczba pakietów na sekundę (PPS):

#v(0.5em)
#align(center)[
  #cetz.canvas({
    chart.columnchart(
      size: (12, 4.8),
      label-key: 0,
      value-key: (1, 2),
      udp_ps_data,
      x-label: [Rozmiar datagramu UDP (przy docelowym bitrate 500 Kbit/s)],
      y-label: [Przepustowość (Kbit/s)],
      y-max: 600,
      mode: "clustered",
      labels: ([Nadawca (Sender)], [Odbiorca (Receiver)]),
      legend: "inner-north-west",
    )
  })
  #v(0.2em)
  #text(size: 9pt, style: "italic")[Rys. 3: Porównanie przepustowości UDP (500K) w zależności od rozmiaru pakietu (`03_udp_packetsize.txt`).]
]

Przy pakietach `64 B` (~976 PPS) łącze ulega natychmiastowemu zatkaniu (odbiorca odbiera średnio zaledwie 15,7 Kbit/s), natomiast przy pakietach `1400 B` (~45 PPS) osiąga pełne *499 Kbit/s* bez utraty ani jednego datagramu.

=== Analiza transmisji TCP i zjawiska Bufferbloat (`04_tcp_raw.json`)

Analiza danych wczytanych bezpośrednio z pliku `04_tcp_raw.json` pokazuje ekstremalny wzrost opóźnienia (Bufferbloat) wynikający z przepełnienia kolejek (`qlen 1000` / `qlen 500`) oraz skokową pracę transmisji (wyrzuty bloków 128 KB widoczne na wykresie przepustowości).

#v(0.5em)
#align(center)[
  #cetz.canvas({
    plot.plot(
      size: (14, 5.2),
      x-label: [Czas trwania testu (s)],
      y-label: [Opóźnienie RTT (ms)],
      x-min: 0, x-max: 10.5,
      y-min: 0, y-max: 800,
      x-grid: "major",
      y-grid: "major",
      legend: "inner-south-east",
      {
        plot.add(
          tcp_rtt_pts,
          style: (stroke: 1.5pt + red.darken(20%)),
          mark: "o",
          mark-size: 0.12,
          mark-style: (fill: red.darken(20%), stroke: none),
          label: [TCP RTT (ms) — z `04_tcp_raw.json`],
        )
        plot.add(
          tcp_cwnd_pts.map(p => (p.at(0), p.at(1) * 10.0)), // skalowanie x10 dla czytelności na wspólnej osi
          style: (stroke: (paint: blue.darken(20%), thickness: 1.2pt, dash: "dashed")),
          label: [Okno przeciążenia `snd_cwnd` (KiB × 10)],
        )
      }
    )
  })
  #v(0.2em)
  #text(size: 9pt, style: "italic")[Rys. 4: Narastanie opóźnienia TCP RTT (Bufferbloat do 719,4 ms) oraz zmiany okna `snd_cwnd` w czasie.]
]

#v(0.5em)
#align(center)[
  #cetz.canvas({
    plot.plot(
      size: (14, 4.2),
      x-label: [Czas trwania testu (s)],
      y-label: [Bitrate nadawcy (Kbit/s)],
      x-min: 0, x-max: 10.5,
      y-min: 0, y-max: 2500,
      x-grid: "major",
      y-grid: "major",
      legend: "inner-north-east",
      {
        plot.add(
          tcp_bps_pts,
          style: (stroke: 1.3pt + green.darken(30%), fill: green.lighten(85%)),
          hypograph: true,
          label: [Chwilowa przepustowość nadawcy TCP (Kbit/s)],
        )
      }
    )
  })
  #v(0.2em)
  #text(size: 9pt, style: "italic")[Rys. 5: Skokowy charakter nadawania bloków 128 KB przez gniazdo TCP (`04_tcp_raw.json`).]
]

=== Wnioski i rekomendacje optymalizacyjne

1. *Ujednolicenie MTU:* Zmniejszenie MTU na interfejsie nadawczym `enp4s0f3u2` z 1500 B do 1400 B (`ip link set dev enp4s0f3u2 mtu 1400`), aby dopasować je do interfejsu odbiorczego `sl0`. Chociaż po zmianie MTU na 1400 B, komenda `ip` dalej reportowała mtu na poziomie 1500 B. 
2. *Eliminacja zjawiska Bufferbloat:* Zmniejszenie parametru `txqueuelen` z `1000`/`500` do wartości `15` na obu interfejsach (`ip link set dev enp4s0f3u2 txqueuelen 15`), co ograniczy opóźnienie TCP RTT z ponad 700 ms do kilkudziesięciu milisekund.
3. *Wdrożenie Traffic Shapingu (Pacingu):* Skonfigurowanie kolejki `cake` na interfejsie nadawczym (`tc qdisc replace dev enp4s0f3u2 root cake bandwidth 450kbit besteffort`), aby równomiernie dawkować pakiety i zapobiegać zatykaniu buforów sprzętowych USB.

=== Analiza przyczyn degradacji wydajności dla małych pakietów 

Szczegółowa analiza kodu źródłowego węzłów ESP32-S3 (`s3_ncm`), ESP32-C3 (`c3_slip`) oraz współdzielonej warstwy transportowej (`espnow_common`) wskazuje, że głównym ograniczeniem badanego łącza nie jest przepustowość bitowa kanału radiowego, lecz maksymalna liczba pakietów przetwarzanych w jednostce czasu (PPS, _packets per second_). Zjawisko to najsilniej dotyka pakiety o małym rozmiarze (datagramy 64 B, pakiety sterujące oraz zwrotne potwierdzenia TCP ACK), co bezpośrednio tłumaczy wyniki zarejestrowane w pliku `04_tcp_raw.json`.

==== Zidentyfikowane ograniczenia w architekturze oprogramowania mikrokontrolerów

1. Synchroniczny model transmisji
   Funkcja `espnow_send_packet` po każdym wywołaniu `esp_now_send` blokuje zadanie `espnow_tx_task` na semaforze binarnym `espnow_tx_sem` (z limitem czasu `15 ms`) do momentu otrzymania przerwania zwrotnego `on_espnow_send`. Pomimo dostępności 32 dynamicznych buforów nadawczych w sterowniku Wi-Fi (`CONFIG_ESP_WIFI_DYNAMIC_TX_BUFFER_NUM=32`), w warstwie radiowej w danej chwili może znajdować się wyłącznie jedna ramka. Ponadto brak konfiguracji przepływności PHY dla ESP-NOW powoduje emisję z domyślną prędkością 1 Mbit/s (802.11b), gdzie stały narzut warstwy fizycznej i MAC (preambuła 192 $mu$s, nagłówki 802.11, DIFS, backoff, SIFS, ACK oraz 6-bajtowy nagłówek `frag_hdr_t`) jest identyczny niezależnie od tego, czy ramka przenosi 244 B danych, czy pojedynczy 52-bajtowy pakiet TCP ACK. Brak mechanizmu agregacji (_coalescing_) sprawia, że każdy mały pakiet IP generuje osobną transakcję radiową.

2. Stałorozmiarowe bufory kolejkowe i limitowanie w pakietach zamiast w bajtach
   Struktura `pkt_item_t` zawiera statyczny bufor o rozmiarze `MAX_PACKET_SIZE` (1600 B), przez co każdy element kolejek `espnow_tx_q` (32 sloty), `usb_tx_q` (32 sloty) oraz `slip_tx_q` (24 sloty) zajmuje ok. 1616 B pamięci niezależnie od rzeczywistej długości pakietu. W rezultacie dla dużych segmentów (~1400 B) kolejka nadawcza buforuje ok. 44,8 KB danych, natomiast dla pakietów 64-bajtowych jej pojemność spada do zaledwie ~2 KB, wymuszając każdorazowe kopiowanie całych bloków 1616 B w pamięci RAM.

3. Blokowanie kontekstów I/O i ciche odrzucanie pakietów
   Zarówno callback odbiorczy stosu TinyUSB (`usb_ncm_recv_cb` w `s3_ncm`), jak i callback radiowy `on_espnow_recv` oraz dekoder `slip_rx_task` (`c3_slip`) wywołują funkcję `xQueueSend` z limitem czasu `10 ms` bez weryfikacji wartości zwracanej. Po zapełnieniu 32 slotów kolejki `espnow_tx_q` nadmiarowe pakiety są po cichu odrzucane, a 10-milisekundowe blokowanie wątku TinyUSB wstrzymuje opróżnianie buforów NTB USB Full-Speed (12 Mbit/s). Na jednordzeniowym układzie ESP32-C3 dodatkowo zadanie `slip_rx_task` posiada wyższy priorytet (6) niż zadanie nadawcze `espnow_tx_task` (5), co przy wysokim PPS prowadzi do wywłaszczania nadajnika radiowego.

4. Brak obsługi błędów transmisji L2 oraz asymetria ścieżki USB
   Procedura `on_espnow_send` ignoruje parametr statusu (`ESP_NOW_SEND_SUCCESS` / `ESP_NOW_SEND_FAIL`), przez co ramki utracone w wyniku kolizji na współdzielonym kanale 1 nie są retransmitowane w warstwie łącza. Po stronie odbiorczej S3 funkcja `usb_tx_task` wykorzystuje synchroniczne wywołanie `tinyusb_net_send_sync` (limit `50 ms`) na interfejsie USB 12 Mbit/s, natomiast na C3 w `slip_tx_task` przekroczenie limitu `10 ms` powoduje przerwanie zapisu ramki bez wysłania znacznika końca `SLIP_END` (`0xC0`), skutkując uszkodzeniem kolejnego pakietu.

==== Korelacja z wynikami testu TCP (`04_tcp_raw.json`)

Zarejestrowany przebieg transmisji TCP (`tcp_mss_default = 1348` B, bloki zapisu `131072` B) stanowi bezpośrednią ilustrację opisanych mechanizmów:

#figure(
  table(
    columns: (0.5fr, 0.5fr, 1fr),
    inset: 6pt,
    align: (left, left, left),
    [*Zjawisko w `04_tcp_raw.json`*], [*Wartość zmierzona*], [*Przyczyna w kodzie*],
    [Narastanie opóźnienia RTT (_Bufferbloat_)],
    [Wzrost z `258,9 ms` (`0,0–0,5 s`) do `719,4 ms` (`8,5–9,0 s`); średnio `600,9 ms`],
    [Okno `snd_cwnd` (`39–47 KB`, tj. ~29–35 segmentów) całkowicie wypełnia 32 sloty kolejki `espnow_tx_q`. Przy przepustowości odbiornika `358,9 kbit/s` czas opróżnienia kolejki i powrotu małych pakietów ACK osiąga ok. 600–720 ms.],

    [Skokowy charakter transmisji (`bytes: 0`)], [14 z 20 półsekundowych przedziałów z zerowym zapisem aplikacji], [Po zapełnieniu buforów gniazdo nadawcze blokuje się, a małe zwrotne pakiety TCP ACK z ESP32-C3 konkurują na tym samym kanale radiowym (w kolejce FIFO bez priorytetyzacji) ze strumieniem 6-fragmentowych segmentów danych.],

    [Retransmisje TCP], [Łącznie 6 retransmisji (`2` w `1,5–2,0 s`, `1` w `8,0–8,5 s`, `3` w `8,5–9,0 s`)], [Przekroczenie pojemności 32 slotów `espnow_tx_q` przy `snd_cwnd > 41 KB` skutkuje cichym odrzucaniem pakietów w `usb_ncm_recv_cb` oraz stratami na kolizjach radiowych bez retransmisji w `on_espnow_send`.],

    [Rozbieżność danych i długie drenowanie], [Nadawca: `655 360 B` (`10,00 s`); Odbiorca: `524 288 B` (`11,69 s`)], [Różnica `131 072 B` pozostaje zakolejkowana w buforach w momencie zakończenia testu, a opróżnienie potoku transmisyjnego trwa jeszcze `1,68 s` po zatrzymaniu nadawcy.],
  ),
  caption: [Powiązanie parametrów transmisji TCP z ograniczeniami implementacji.]
)

W świetle powyższej implementacji i ograniczonej funkcjonalności nie było możliwe przetestowanie korzystając z rozwiązania #link("https://github.com/tfo-dot/patronus")[Patronus] - autorski system komunikacji Peer-to-Peer.

= Analiza oprogramowania

Do każdego wektoru ataku czy możliwości wykorzystania zabezpieczeń dołączone są zalecenia aby w przyszłości, na wypadek naprawy czy kontynuacji prac nad projektem naprawić wymienione problemy i wiedzieć czego się spodziewać. Dodatkowo, my, jako projektanci systemu jesteśmy w pełni świadomi zagrożeń wynikających z jego korzystania, odradzając korzystanie w środowiskach które wymagają niezawodności i bezpieczeństwa przesyłanych danych.

== Pasywna analiza ruchu

=== Opis zagrożenia

Pasywna analiza ruchu to metoda badania i monitorowania komunikacji w sieciach teleinformatycznych bez jakiejkolwiek ingerencji w strukturę przesyłanych pakietów oraz bez generowania dodatkowego obciążenia sieciowego.

=== Analiza w projekcie

- Brak szyfrowania w warstwie łącza: W `espnow_add_or_update_peer` pole peer.encrypt jest ustawione na false, a w projekcie nie ma żadnych wywołań `esp_now_set_pmk` ani konfiguracji LMK. Cały ruch jest tekstem jawnym na stałym kanale 1.
- Jawność metadanych i topologii: Zadanie `espnow_discovery_task` co 2000 ms rozgłasza na adres broadcast jawny pakiet z magic 0x4E494344 (NICD), typem komunikatu, adresem MAC STA nadawcy, rolą węzła (ESPNOW_NODE_S3_NCM = 1, ESPNOW_NODE_C3_SLIP = 2), adresem IPv4 oraz uptime_s. Pasywny obserwator w trybie monitor od razu mapuje całą topologię, role urządzeń i momenty restartów.
- Jawność ruchu danych: Nagłówek fragmentacji i kolejne fragmenty przenoszą surowe pakiety IP, cały nieszyfrowany ruch L3–L7 (DNS, HTTP, ICMP, nagłówki TCP/UDP, adresy docelowe) jest bezpośrednio czytelny.     
                                                                                                                    
=== Środki zaradcze                                                                                            
- Aktywacja szyfrowania ESP-NOW (peer.encrypt = true + PMK/LMK) dla ruchu unicast.
- Ze względu na brak szyfrowania ramek broadcast w ESP-NOW, ograniczenie lub wyłączenie okresowych beaconów po sparowaniu oraz wdrożenie szyfrowania w warstwie sieciowej/transportowej (np. WireGuard/IPsec między hostami PC1–PC2 lub szyfrowany tunel w warstwie aplikacji).

== Ataki aktywne w warstwie łącza danych

=== Opis zagrożenia

Zagrożenie to (znane jako MAC spoofing połączony z iniekcją ramek w warstwie 2 modelu OSI) polega na złamaniu podstawowego mechanizmu identyfikacji urządzeń w sieci lokalnej (LAN), co pozwala atakującemu na podszycie się pod zaufany host.

=== Analiza w projekcie

- Brak uwierzytelniania i automatyczne dodawanie nieznanych węzłów przyjmuje ramki od dowolnego adresu.
  - Każda ramka z magic 0x4E494344 trafia do `espnow_handle_discovery_pkt`, co automatycznie dodaje info->src_addr i deklarowany adres disc->ip do tablicy s_peers.
  - Nawet zwykła ramka danych wywołuje `espnow_peer_table_touch`, która przy nieznanym adresie MAC automatycznie dodaje go do s_peers.
- Podrobienie MAC, zatrucie mapowania IP→MAC i przejęcie sesji
  - Po reasemblacji dowolnego pakietu spełniającego `(ip_hdr[0] >> 4) == 4` oraz `ip_len >= 20`, `espnow_reasm_process_src` bezwarunkowo aktualizuje adres IP przypisany do src_mac przez `espnow_peer_table_update_ip(src_mac, src_ip)`.
- `espnow_peer_table_find_by_ip()` zwraca pierwszy aktywny wpis z pasującym IP bez weryfikacji unikalności IP w tabeli; jednocześnie `espnow_peer_table_add()` przy pełnej tablicy (ESPNOW_MAX_PEERS = 16) wywłaszcza najstarszego niestatycznego peera. Pozwala to na wyparcie uprawnionego węzła lub przekierowanie ruchu wychodzącego dla danego IP.
- Wstrzykiwanie fałszywych pakietów IP do hosta:
  - W kodzie specyficznym dla S3: `on_espnow_recv()` po złożeniu ramki w `espnow_reasm_process_src` przepisuje lokalny host_mac jako cel Ethernet i remote_mac (02:00:00:00:00:02) jako źródło, wysyłając pakiet przez usb_tx_q wprost do interfejsu sieciowego hosta, bez sprawdzania, czy `info->src_addr` jest autoryzowanym peerem.
  - W kodzie specifycznym dla C3: analogicznie każdy złożony pakiet trafia bez filtrowania do `slip_tx_q` na port szeregowy hosta.
- Zakłócanie reasemblacji fragmentów
 - Sloty s_default_rx_slots[REASM_SLOTS] (REASM_SLOTS = 8) identyfikują strumień wyłącznie przez (src_mac, frame_id).
 - s_tx_frame_id jest prostym sekwencyjnym licznikiem od 0, co czyni go przewidywalnym. 
 - Napastnik podszywający się pod src_mac może wstrzyknąć fragment z tym samym frame_id, nadpisując bufor slot->pkt.data. Ponadto expected_mask jest wyliczane z `pkt->hdr.frag_total` ostatnio odebranego fragmentu, a nie zapamiętane z pierwszego fragmentu, co pozwala na przedwczesne zamknięcie niekompletnego pakietu (np. przez wstrzyknięcie pojedynczego fragmentu z frag_total = 1).
 - Dodatkowo w `espnow_handle_discovery_pkt` / `espnow_discovery_task` zapis i odczyt `s_resp_target_mac` oraz `s_need_send_resp` odbywają się bez synchronizacji (data race między zadaniem Wi-Fi a zadaniem discovery).

=== Środki zaradcze
- Wyłączenie automatycznej rejestracji nieznanych MAC w espnow_peer_table_touch() i espnow_handle_discovery_pkt(); stosowanie statycznej/uwierzytelnionej listy peerów.
- Dodanie uwierzytelnionego nagłówka (HMAC/AEAD z licznikiem lub nonce) w warstwie fragmentacji lub włączenie CCMP.
- Zapisywanie `frag_total` w strukturze reasm_slot_t przy pierwszym fragmencie i odrzucanie fragmentów o niezgodnym `frag_total`.
- Wymuszenie unikalności IP w `s_peers` oraz zabezpieczenie przed nadpisywaniem IP zapisanego peera przez inny MAC.

== Ataki na dostępność

Ataki na dostępność (DoS – Denial of Service) to rodzaj cyberataków, których głównym celem jest uniemożliwienie uprawnionym użytkownikom dostępu do konkretnego systemu, usługi sieciowej, strony internetowej lub zasobu obliczeniowego.

W przeciwieństwie do ataków polegających na kradzieży danych czy przejęciu kontroli nad maszyną, atak DoS skupia się na paraliżu działania poprzez wyczerpanie zasobów ofiary (np. przepustowości łącza, pamięci RAM, mocy procesora lub limitu otwartych połączeń) albo wykorzystanie błędu w oprogramowaniu powodującego awarię usługi.

=== Analiza w projekcie
+ Out-of-Bounds Read (odczyt poza bufor wejściowy) w `espnow_reasm_process_src`
  - Weryfikowany jest tylko minimalny rozmiar nagłówka: `len < (int)sizeof(frag_hdr_t)` (6 bajtów).
  - Sprawdzane jest `pkt->hdr.payload_len > MAX_FRAG_PAYLOAD` (244 B), brakuje natomiast sprawdzenia `sizeof(frag_hdr_t) + pkt->hdr.payload_len <= (size_t)len`.
  - Przy odebraniu krótkiej ramki ESP-NOW (np. len = 6) z zadeklarowanym payload_len = 244, warunek bufora wyjściowego (`header_offset + offset + payload_len <= MAX_PACKET_SIZE`) jest spełniony, więc `memcpy(slot->pkt.data + header_offset + offset, pkt->data, pkt->hdr.payload_len)` odczytuje do 238 bajtów pamięci poza końcem bufora data (fragmenty sąsiednich buforów sterownika Wi-Fi/ESP-NOW), mogąc powodować naruszenie ochrony pamięci lub wyciek danych sąsiednich w pamięci do hosta.
+ Brak walidacji spójności indeksów i wyciek zawartości między slotami
  - Brakuje warunku `pkt->hdr.frag_idx < pkt->hdr.frag_total`. Przy `frag_total` = 1 i `frag_idx` = 6 dane trafiają na offset 1464, ale slot nigdy nie osiąga `expected_mask`.
  - Bufor slot->pkt.data nie jest zerowany przy alokacji/ponownym użyciu slotu. Jeśli napastnik wyśle ostatni fragment z `payload_len` = 0 i wcześniejszy z `payload_len = 1`, `slot->total_len` wynosi `offset + 0`, co pozostawia w środku `pkt->data` niezerowane pozostałości poprzedniego pakietu z tego slotu.
+ Blokowanie zadania Wi-Fi ESP-IDF przez kolejki RX
  - Funkcje on_espnow_recv() działają w kontekście systemowego zadania Wi-Fi i używają blokującego `xQueueSend(..., pdMS_TO_TICKS(10))`.
  - Przy zalewaniu radia jednopakietowymi ramkami (frag_idx=0, frag_total=1) lub gdy host przestanie odbierać dane z USB/TTY, kolejki `usb_tx_q` (32) / `slip_tx_q` (24) zapełniają się, a zadanie Wi-Fi jest usypiane na 10 ms przy każdej nadchodzącej ramce. Skutkuje to utratą ramek sterujących, przepełnieniem puli buforów RX Wi-Fi i potencjalnym wywołaniem restartu układu.
+ Wyczerpanie tablicy peerów i slotów reasemblacji
  - `REASM_SLOTS = 8`: wysyłanie pojedynczych fragmentów z różnymi frame_id / src_mac stale nadpisuje najstarszy aktywny slot, całkowicie uniemożliwiając złożenie wielofragmentowych pakietów uprawnionych węzłów.
  - ESPNOW_MAX_PEERS = 16 (przy limicie ESP-NOW w sterowniku Wi-Fi = 20 wszystkich peerów, w tym broadcast): zalewanie ramkami z losowymi adresami źródłowymi MAC wymusza ciągłe wywołania esp_now_del_peer / esp_now_add_peer z kontekstu RX, wywłaszczając legalne węzły.
  - Ciągłe wysyłanie ramek DISCOVERY BEACON wyzwala espnow_discovery_task do ciągłego nadawania odpowiedzi i zajmowania `s_tx_mutex`, co głodzi espnow_send_packet() (w którym jeden zablokowany pakiet potrafi trzymać `s_tx_mutex` przez kilkaset ms z uwagi na pętlę retries = 20 i `xSemaphoreTake(..., 15 ms)`).
+ Pamięć Heap. W ścieżce przetwarzania pakietów brak dynamicznych alokacji (malloc/calloc), wszystkie bufory są statyczne lub w kolejkach utworzonych w app_main, więc klasyczne wyczerpanie sterty w kodzie aplikacji nie występuje; wyczerpywane są wyłącznie bufory sterownika Wi-Fi (ESP_ERR_ESPNOW_NO_MEM), kolejki FreeRTOS i tablice stałe.

=== Środki zaradcze:                                                                                                            
- Dodać w `espnow_reasm_process_src` warunki:
 - `len < (int)sizeof(frag_hdr_t) + (int)pkt->hdr.payload_len)`
 - `pkt->hdr.frag_idx >= pkt->hdr.frag_total`
- Zerowanie nieużywanych obszarów lub walidację dokładnej długości w każdym fragmencie (`payload_len == MAX_FRAG_PAYLOAD` dla wszystkich fragmentów poza ostatnim).
- Zmienić `xQueueSend(..., pdMS_TO_TICKS(10))` w obu `on_espnow_recv` na wariant nieblokujący, odrzucając nadmiarowe pakiety zamiast blokować zadanie Wi-Fi.
- Ograniczyć częstotliwość odpowiedzi discovery i nie dodawać automatycznie nieznanych MAC do tabeli peerów.

== Analiza kryptograficzna

Analiza kryptograficzna (kryptoanaliza) w sieciach teleinformatycznych to proces badania i łamania mechanizmów zabezpieczeń kryptograficznych używanych podczas przesyłania danych, mający na celu odzyskanie oryginalnej treści (tekstu jawnego) lub kluczy szyfrujących bez posiadania do nich autoryzowanego dostępu.

Obejmuje także analizę implementacji protokołów sieciowych (np. TLS, IPsec, WPA3, SSH) i samego ruchu sieciowego.

=== Analiza w projekcie

- Brak wdrożenia CCMP w aktualnym kodzie: Mimo obecności domyślnych flag kompilacji w sdkconfig (`CONFIG_ESP_WIFI_ESPNOW_MAX_ENCRYPT_NUM=7`, `CONFIG_ESP_WIFI_MBEDTLS_CRYPTO=y`), kod nigdy nie wywołuje `esp_now_set_pmk` i jawnie wyłącza szyfrowanie dla każdego peera (`peer.encrypt = false`).
- Ograniczenia i podatności mechanizmu CCMP w ESP-NOW przy ewentualnym włączeniu
  + Limit peerów i brak ochrony broadcastu: ESP-NOW obsługuje szyfrowanie AES-128-CCMP (klucz LMK per peer, szyfrowany lokalnie przez PMK w sterowniku Wi-Fi) maksymalnie dla siedmiu peerów, podczas gdy w projekcie `ESPNOW_MAX_PEERS = 16`. Ponadto ESP-NOW nie szyfruje ramek broadcast, obecne `espnow_send_discovery_beacon` oraz fallback na `s_broadcast_mac` w `espnow_resolve_dest_mac` pozostałyby całkowicie jawne i podatne na fałszowanie.
  + Ponowne użycie nonce (Nonce Reuse) po restarcie: Stos Wi-Fi/ESP-NOW w ESP-IDF przechowuje liczniki pakietów (PN, budujące wektor inicjalizujący / nonce dla AES-CCM) wyłącznie w pamięci ulotnej RAM, bez zapisu w NVS. Przy zastosowaniu statycznego klucza LMK, każdy restart zasilania lub wymuszony reboot (np. przez atak DoS) resetuje PN do wartości początkowej. Ponowne użycie tej samej pary (LMK, nonce) w trybie AES-CTR łamie poufność (atak przez XOR szyfrogramów odzyskuje XOR tekstów jawnych) i osłabia gwarancje integralności.
  + Podatność na ataki powtórzeniowe, po resecie odbiornika stan okna wykrywania powtórzeń dla danego statycznego LMK zostaje wyzerowany, co pozwala na ponowne odtworzenie wcześniej przechwyconych ramek Action Frame z poprzedniej sesji.
  + Zarządzanie kluczami PMK/LMK: W obecnej architekturze brak protokołu uzgadniania kluczy (key exchange) i brak szyfrowania NVS (`#CONFIG_NVS_ENCRYPTION is not set`), więc wgranie statycznych kluczy wiązałoby się z ich stałą ekspozycją w pamięci Flash.

=== Środki zaradcze

Zamiast polegać wyłącznie na statycznym LMK w CCMP, należy wdrożyć po stronie aplikacji lub hosta uwierzytelnione uzgadnianie efemerycznych kluczy sesyjnych (np. ECDH + PSK/podpis z losowym nonce sesyjnym) lub tunelowanie warstwy IP przez WireGuard (który zapewnia odporność na replay i rotację kluczy niezależnie od warstwy 802.11).


= Ataki fizyczne i bezpieczeństwo hosta

== Ataki fizyczne

Ataki fizyczne polegają na bezpośredniej ingerencji w sprzęt w celu odczytania pamięci, ominięcia zabezpieczeń lub przejęcia kontroli nad wykonaniem kodu.

- Wykorzystanie interfejsów debugowania, pozostawione aktywne na płytce PCB złącza serwisowe pozwalają atakującemu podłączyć programator, zrzucić zawartość pamięci Flash/RAM, podejrzeć rejestry procesora lub wstrzyknąć własny firmware.
- Podsłuch i modyfikacja magistral komunikacyjnych, wpięcie analizatora logicznego w linie SPI, I2C lub UART łączące mikrokontroler z zewnętrzną pamięcią Flash, EEPROM lub modułami radiowymi. Pozwala to przechwycić niezaszyfrowany firmware, klucze kryptograficzne lub dane uwierzytelniające podczas ich przesyłania.
- Bezpośredni odczyt pamięci, wylutowanie układu pamięci (np. NAND/NOR Flash) i odczytanie jego zawartości w zewnętrznym programatorze, gdy sam mikrokontroler ma zablokowane interfejsy debugowania.
- Analiza kanałów bocznych, nieinwazyjne badanie fizycznych parametrów pracy układu podczas operacji kryptograficznych:
  - SPA / DPA (Simple / Differential Power Analysis): Analiza wahań poboru prądu przez mikrokontroler w celu odtworzenia klucza szyfrującego (np. AES).
  - Analiza elektromagnetyczna (EMA): Pomiar promieniowania EM emitowanego przez rdzeń procesora.
- Wstrzykiwanie błędów, celowe zakłócanie warunków pracy układu w precyzyjnie wyliczonym ułamku sekundy (poprzez gwałtowny spadek napięcia, zakłócenie sygnału zegarowego lub impuls elektromagnetyczny/laserowy). Powoduje to przeskoczenie instrukcji procesora, np. pominięcie warunku sprawdzającego podpis cyfrowy firmware'u lub odblokowanie chronionej pamięci.

=== Ekstrakcja pamięci Flash i inżynieria wsteczna

Konfiguracje pokazują brak sprzętowych zabezpieczeń przed dostępem fizycznym:
- `# CONFIG_SECURE_BOOT is not set` - brak weryfikacji podpisu obrazów aplikacji.
- `# CONFIG_SECURE_FLASH_ENC_ENABLED is not set` - brak szyfrowania XTS-AES pamięci Flash.
- `# CONFIG_NVS_ENCRYPTION is not set` - partycja NVS (gdzie zwykle trafiają dane Wi-Fi/klucze) nie jest szyfrowana.
- `CONFIG_SECURE_ROM_DL_MODE_ENABLED=y` - aktywny tryb ROM Download Mode (UART/USB).
- Na S3 dodatkowo aktywne są `CONFIG_ESP_CONSOLE_UART_DEFAULT=y` oraz `CONFIG_ESP_CONSOLE_SECONDARY_USB_SERIAL_JTAG=y`.

=== Konsekwencje
Fizyczny dostęp do płytki (przez UART/USB w trybie download lub bezpośrednio do kości SPI Flash) pozwala odczytać pełny obraz firmware w postaci jawnej, zdekompilować logikę (Xtensa LX7 dla S3 / RISC-V dla C3) oraz wydobyć ewentualnie wkompilowane klucze PMK/LMK. Brak Secure Boot umożliwia ponadto wgranie zmodyfikowanego, złośliwego firmware na ten sam układ.

== Bezpieczeństwo hosta

Podłączenie nieznanego, skompromitowanego lub błędnie zaprogramowanego układu ESP32 otwiera dla potencjalnego atakującego bezpośredni wektor wejścia do systemu operacyjnego hosta:
- Ataki typu BadUSB i emulacja peryferiów (ESP32-S2 / S3): Mikrokontrolery wyposażone w natywny kontroler USB OTG mogą w ułamku sekundy przedstawić się systemowi jako klawiatura/mysz (HID) i wstrzyknąć ciąg poleceń w terminalu hosta, albo jako karta sieciowa (USB NCM / RNDIS), przejmując ruch sieciowy (np. poprzez fałszywy serwer DHCP/DNS).
- Eksploatacja stosu USB i sterowników jądra: Spreparowane deskryptory urządzeń USB lub zniekształcone ramki przesyłane przez magistralę mogą wywołać przepełnienie bufora lub błędy pamięci w sterownikach systemowych (np. cdc_acm, cp210x, ch341).
- Wstrzykiwanie sekwencji terminala przez UART: Monitorowanie portów szeregowych (`/dev/ttyUSB*`, `/dev/ttyACM*`) bez filtrowania danych pozwala urządzeniu wysłać złośliwe sekwencje ucieczki `ANSI/VT100`. W podatnych emulatorach terminala może to prowadzić do manipulacji schowkiem, zmiany konfiguracji okna, a w skrajnych przypadkach do zdalnego wykonania kodu.
- Uszkodzenia fizyczne i elektryczne: Błędne podłączenie zasilania (np. podanie 12V/24V na piny GPIO lub linię 3.3V/5V) albo celowo zmodyfikowany układ (USB Killer) może trwale uszkodzić kontroler USB i płytę główną hosta.

=== Analiza w projekcie

- Złośliwe lub uszkodzone deskryptory USB
  - W aktualnym stanie kodu S3 używa standardowych deskryptorów espressif/esp_tinyusb (`TINYUSB_DEFAULT_CONFIG`, tryb `CONFIG_TINYUSB_NET_MODE_NCM=y`, bufory NTB 3200 B), a C3 używa wbudowanego kontrolera `USB-Serial`/`JTAG ESP32-C3`. Same oryginalne deskryptory są statyczne i poprawne.
  - Ryzyko pojawia się przy fizycznym dostępie: zmodyfikowane urządzenie S3 może prezentować jądru hosta celowo uszkodzone deskryptory USB (nieprawidłowe długości deskryptorów funkcjonalnych NCM, błędne wMaxPacketSize lub nietypowe liczby punktów końcowych) bądź złośliwe ramki agregacji NCM NTB (`NTH16`/`NDP16`) przekazywane do sterowników jądra (`cdc_ncm.c` w Linuksie, `UsbNcm.sys` w Windows), które historycznie bywały źródłem błędów dereferencji/przepełnień (Kernel Panic / BSOD) w niezałatanych jądrach. Urządzenie może także podszyć się pod inne klasy USB (np. HID/MSC).
- Spreparowane pakiety z ESP32 do sterownika jądra hosta
  - Przez S3, `on_espnow_recv` przekazuje każdy złożony bufor z radia (o dowolnej długości `15..1600` bajtów po doklejeniu 14B Ethernet) poprzez `tinyusb_net_send_sync` bezpośrednio do jądra hosta (sk_buff / NET_BUFFER_LIST). Firmware nie sprawdza, czy zawartość stanowi poprawny pakiet `IPv4`/`IPv6`. Zdalny napastnik radiowy może wysyłać dowolnie zniekształcone nagłówki L3/L4 bezpośrednio do stosu sieciowego jądra hosta, a także wykorzystać lukę OOB-read w `espnow_reasm_process_src` do wstrzyknięcia losowych fragmentów pamięci `ESP32`.
  - Przez S3 `handle_dhcp`, firmware lokalnie odpowiada na DHCP, przydzielając hostowi adres `10.0.0.1/24` z bramą domyślną `10.0.0.2`, co bez jawnych reguł routingu na hoście może spowodować kierowanie ruchu systemowego przez niezaufany interfejs radiowy.
  - Przez C3, strumień SLIP jest parsowany w Linuksie przez dyscyplinę linii w przestrzeni jądra (`drivers/net/slip/slip.c`, `N_SLIP`). Pakiety z radia do 1600 B trafiają bezpośrednio do dekodera SLIP w jądrze (należy upewnić się, że MTU interfejsu `sl*` jest zgodne z `MAX_PACKET_SIZE`, a sterownik jest aktualny).

= Analiza z wykorzystaniem symulacji

== Wyniki uruchomionych symulacji

```
~/Documents/netcard/sims> julia sim_discovery_race.jl 
=== SYMULACJA WYŚCIGU W MECHANIZMIE DISCOVERY (s_resp_target_mac Race Condition) ===
Topologia (liczba węzłów)            |  Czas pełnego mesh |   Nadpisane odpowiedzi
------------------------------------------------------------------------------------
2 węzłów (rozrzut startu 10 ms)      |             5.9 ms |                      0
5 węzłów (rozrzut startu 20 ms)      |            18.9 ms |                      4
10 węzłów (rozrzut startu 20 ms)     |            18.9 ms |                     45
15 węzłów (rozrzut startu 15 ms)     |            14.1 ms |                    153
20 węzłów (rozrzut startu 10 ms)     |             9.5 ms |                    322
~/Documents/netcard/sims> julia sim_dos_jamming.jl 
=== SYMULACJA WPŁYWU ATAKU DoS I ZAKŁÓCEŃ NA PRZEPUSTOWOŚĆ ESP-NOW ===
Scenariusz                                 |    Goodput |    Straty |  Opóźnienie | Przyczyna strat (Q / NoMem / Air)
---------------------------------------------------------------------------------------------------------
1. Warunki idealne (brak DoS, PER=1%)      |  1253.3 kb/s |     6.8 % |     5.44 ms | 0 / 0 / 81
2. Umiarkowane zakłócenia RF (PER=15%)     |   384.2 kb/s |    71.4 % |   349.92 ms | 258 / 0 / 565
3. Silne zakłócenia RF (PER=35%)           |    45.9 kb/s |    96.6 % |  1062.92 ms | 555 / 0 / 487
4. Lekki atak DoS (800 pps) + PER=5%       |   219.5 kb/s |    83.7 % |   855.66 ms | 436 / 0 / 464
5. Silny atak DoS (2200 pps) + PER=5%      |     6.7 kb/s |    99.5 % |  1913.25 ms | 915 / 61 / 134
~/Documents/netcard/sims> julia sim_fragmentation_vuln.jl 
=== SYMULACJA PODATNOŚCI MECHANIZMU FRAGMENTACJI (espnow_reasm_process_src) ===

--- Test 1: Atak wyparcia slotów (Slot Eviction / Starvation) ---
Stan po 5/6 fragmentach legalnego pakietu: aktywne sloty = 1
Liczba wypartych legalnych sesji: 1
Status ostatniego fragmentu legalnego pakietu: evicted_other (pakiet przepadł mimo odebrania 6/6 fragmentów!)

--- Test 2: Wstrzyknięcie złośliwego fragmentu (Payload Poisoning) ---
Wynik reasemblacji: reassembled_poisoned
Rozmiar złożonego pakietu IP przekazanego do stosu sieciowego: 588 B (w tym 244 B wstrzykniętych przez atakującego)
~/Documents/netcard/sims> 
~/Documents/netcard/sims> julia sim_hol_backing.jl 
=== SYMULACJA HEAD-OF-LINE BLOCKING (s_tx_mutex + espnow_tx_sem) ===
Scenariusz                             |   Odebrane | Straty H1 |  Śr. opóźn. |  P99 opóźn.
--------------------------------------------------------------------------------------------
1. Brak martwego węzła (0 pps)         |       1000 |      0.0% |     5.95 ms |     5.95 ms
2. Rzadki ruch do martwego (2 pps)     |       1000 |      0.0% |    32.49 ms |   106.95 ms
3. Umiarkowany ruch do martwego (8 pps) |        598 |     38.3% |   440.35 ms |   592.75 ms
4. Ciągły ruch do martwego (20 pps)    |        359 |     63.0% |   690.72 ms |   987.08 ms
~/Documents/netcard/sims> julia sim_peer_table_eviction.jl 
=== SYMULACJA WYCZERPANIA TABLICY SĄSIADÓW (s_peers Eviction & Broadcast Fallback) ===
Konfiguracja i natężenie ataku                   |  Wypchnięcia |  Ruch zdegradowany
------------------------------------------------------------------------------------
1. Brak ataku (dynamiczny peer)                  |            0 |              0.0 %
2. Słaby MAC Flood: 15 pps (dynamiczny peer)     |            5 |             35.3 %
3. Średni MAC Flood: 100 pps (dynamiczny peer)   |            5 |             90.4 %
4. Silny MAC Flood: 500 pps (dynamiczny peer)    |            5 |             98.0 %
5. Silny MAC Flood: 500 pps (is_static = true)   |            0 |              0.0 %
~/Documents/netcard/sims> julia sim_usb_espnow_bridge.jl 
=== SYMULACJA MOSTKA USB NCM <-> ESP-NOW (Bufferbloat vs Rozmiar Kolejki) ===
Konfiguracja (tx_q_len / wait_ms)      |    Goodput |    Straty | Śr. kolejka |  Max opóźn.
--------------------------------------------------------------------------------------------
1. Mała kolejka (q=8, wait=2ms)        |   588.0 kb/s |    60.8 % |   159.89 ms |   406.35 ms
2. Średnia kolejka (q=16, wait=5ms)    |   607.0 kb/s |    59.6 % |   350.74 ms |   561.15 ms
3. Obecny sterownik (q=32, wait=10ms)  |   852.3 kb/s |    43.2 % |  1618.51 ms |  3096.00 ms
4. Duża kolejka (q=64, wait=10ms)      |   888.2 kb/s |    40.8 % |  2009.10 ms |  3579.75 ms
5. Obecny sterownik + duże bursty (40) |  1997.0 kb/s |    33.5 % |  3649.79 ms |  7140.15 ms
~/Documents/netcard/sims> julia verify_ccmp_keyspace.jl 
=== WERYFIKACJA TEORETYCZNA PRZESTRZENI KLUCZY CCMP (ESP-NOW) ===

Profil: Obecny sterownik (peer.encrypt = false)
  -> KRYTYCZNY BRAK SZYFROWANIA (peer.encrypt = false w espnow_common.c)
  -> Przestrzeń kluczy |K| = 2^0 = 1 (transmisja otwartym tekstem, pasywny podsłuch = 0 operacji)

Profil: ESP-NOW CCMP (AES-128, standard IEEE 802.11)
 • Rozmiar przestrzeni kluczy |K| : 2^128 ≈ 3.403e+38 kombinacji
 • Czas złamania (klasyczny, 10^21/s): 5.395e+09 lat (3.91e-01 × wiek Wszechświata)
 • Złożoność kwantowa (Grover) : 2^64 operacji (5.849e-10 lat przy 10^21 op/s)
 • Min. energia (granica Landauera): 4.885e+20 J (4.05e-14 lat całkowitej mocy Słońca)
 • Limit 48-bit Nonce (50% kolizji) : 1.975e+07 ramek (wymaga rotacji LMK przed wyczerpaniem)
 • Prawdopodobieństwo sfałszowania MIC: 5.421e-20 (1 próba)

Profil: Hipoteza AES-256 CCMP
 • Rozmiar przestrzeni kluczy |K| : 2^256 ≈ 1.158e+77 kombinacji
 • Czas złamania (klasyczny, 10^21/s): 1.836e+48 lat (1.33e+38 × wiek Wszechświata)
 • Złożoność kwantowa (Grover) : 2^128 operacji (1.079e+10 lat przy 10^21 op/s)
 • Min. energia (granica Landauera): 1.662e+59 J (1.38e+25 lat całkowitej mocy Słońca)
 • Limit 48-bit Nonce (50% kolizji) : 1.975e+07 ramek (wymaga rotacji LMK przed wyczerpaniem)
 • Prawdopodobieństwo sfałszowania MIC: 2.939e-39 (1 próba)

--- Weryfikacja ograniczeń architektonicznych ESP-NOW dla trybu CCMP ---
  • Maksymalna liczba zaszyfrowanych peerów w ESP-IDF: 17 (wobec ESPNOW_MAX_PEERS w RAM)
  • Ramki rozgłoszeniowe (s_broadcast_mac = FF:FF:FF:FF:FF:FF): CCMP w ESP-NOW NIE szyfruje ramek broadcast — pakiety discovery beacon pozostają jawne nawet po włączeniu peer.encrypt = true.
```

== Analiza wąskich gardeł wydajnościowych i synchronizacji

=== Zjawisko wyścigu w protokole wykrywania węzłów

Mechanizm wykrywania topologii bazuje na rozsyłaniu ramek rozgłoszeniowych `BEACON` podczas rozruchu węzła (3 ramki co $200 "ms"$) oraz cyklicznie co $T_"beacon" = 2000 "ms"$. Węzeł odbierający ramkę `BEACON` jest zobligowany do odesłania potwierdzenia w trybie _unicast_ (`RESPONSE`).

Analiza wykazała obecność sekcji krytycznej pozbawionej właściwego kolejkowania. Procedura obsługi przerwania odbiorczego zapisuje adres fizyczny nadawcy do pojedynczego, globalnego bufora jednoslotowego `s_resp_target_mac` i ustawia flagę logiczną `s_need_send_resp = true`. Z uwagi na czas wybudzenia i szeregowania zadania `espnow_discovery_task` przez planistę FreeRTOS ($delta t_"wakeup" approx 3,5 "ms"$), nadejście kolejnej ramki rozgłoszeniowej z innego węzła w oknie czasowym $[t_0, t_0 + delta t_"wakeup"]$ powoduje bezpowrotne nadpisanie adresu docelowego oczekującej odpowiedzi.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (left, right, right, right),
    inset: 6pt,
    stroke: 0.5pt + luma(160),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    [*Liczba węzłów ($N$)*], [*Rozrzut startu*], [*Czas pełnego mesh*], [*Nadpisane odpowiedzi*],
    [2 węzły], [$10 "ms"$], [$5,9 "ms"$], [0],
    [5 węzłów], [$20 "ms"$], [$18,9 "ms"$], [4],
    [10 węzłów], [$20 "ms"$], [$18,9 "ms"$], [45],
    [15 węzłów], [$15 "ms"$], [$14,1 "ms"$], [153],
    [20 węzłów], [$10 "ms"$], [$9,5 "ms"$], [322],
  ),
  caption: [Wyniki symulacji wyścigu na buforze jednoslotowym `s_resp_target_mac` (`sim_discovery_race.jl`).]
)

Liczba utraconych ramek `RESPONSE` rośnie nieliniowo wraz z zagęszczeniem węzłów ($O(N^2)$ w oknie rozruchowym), osiągając 322 nadpisania dla 20 węzłów. Pozorna zbieżność czasu zestawienia pełnej topologii _full-mesh_ (np. $9,5 "ms"$ dla $N=20$) wynika z faktu, że w idealnym kanale radiowym węzły rejestrują sąsiadów pasywnie na podstawie samych ramek rozgłoszeniowych `BEACON`, a czas ten jest zdeterminowany wyłącznie przez wylosowany offset startowy ostatniego węzła (`boot_jitter_ms`). W rzeczywistych warunkach propagacyjnych (gdzie ramki broadcast nie podlegają retransmisji ARQ w warstwie MAC) utrata ramek `RESPONSE` opóźni dołączenie nowego węzła o pełny okres 2000 ms.

=== Blokowanie początku kolejki

Podsystem nadawczy wykorzystuje pojedynczą kolejkę FIFO (`espnow_tx_q` o głębokości $L_q = 32$) oraz synchronizację dostępu do toru radiowego za pomocą muteksu `s_tx_mutex` i semafora binarnego `espnow_tx_sem` z czasem wygaśnięcia $T_"sem" = 15 "ms"$. Przesłanie pakietu IP o rozmiarze zbliżonym do MTU ($1400 - 1500 "B"$) wymaga jego podziału na $M = 7$ fragmentów (maksymalny ładunek użyteczny ramki ESP-NOW wynosi $244 "B"$ po odjęciu $6 "B"$ nagłówka `frag_hdr_t`).

Dla osiągalnego węzła czas obsługi pojedynczego fragmentu (transmisja wraz ze sprzętowym potwierdzeniem ACK warstwy 802.11) wynosi $t_"frag,ok" approx 0,85 "ms"$, co daje łączny czas obsługi pakietu $T_"pkt,ok" = 7 times 0,85 "ms" = 5,95 "ms"$. W sytuacji, gdy docelowy węzeł ulegnie awarii lub opuści zasięg radiowy (przed upływem czasu wygaśnięcia wpisu w tablicy sąsiadów $T_"peer_timeout" = 10000 "ms"$), każdy z 7 fragmentów blokuje zadanie `espnow_tx_task` na pełny czas oczekiwania na semaforze:
$ T_"pkt,dead" = M times T_"sem" = 7 times 15 "ms" = 105 "ms" $

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (left, right, right, right, right),
    inset: 6pt,
    stroke: 0.5pt + luma(160),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    [*Natężenie ruchu do martwego węzła*], [*Dostarczone (H1)*], [*Straty (H1)*], [*Śr. opóźnienie*], [*Kwantyl P99*],
    [$0 "pps"$ (brak martwego węzła)], [1000], [$0,0 %$], [$5,95 "ms"$], [$5,95 "ms"$],
    [$2 "pps"$ (ruch rzadki)], [1000], [$0,0 %$], [$32,49 "ms"$], [$106,95 "ms"$],
    [$8 "pps"$ (ruch umiarkowany)], [598], [$38,3 %$], [$440,35 "ms"$], [$592,75 "ms"$],
    [$20 "pps"$ (ruch ciągły)], [359], [$63,0 %$], [$690,72 "ms"$], [$987,08 "ms"$],
  ),
  caption: [Degradacja transmisji do sprawnego węzła (H1, $100 "pps"$) wskutek blokowania HoL (`sim_hol_backing.jl`).]
)

Brak mechanizmu wczesnego przerywania pętli fragmentacji (_early abort_) po pierwszym błędzie dostarczenia ramki powoduje $17,6$-krotny wzrost czasu zajęcia kolejki przez pojedynczy pakiet. Już przy strumieniu $lambda_"dead" = 8 "pps"$ skierowanym do nieosiągalnego węzła, tor nadawczy jest zablokowany przez $8 times 105 "ms" = 840 "ms"$ w każdej sekundzie, co prowadzi do przepełnienia kolejki `espnow_tx_q` (przekroczenie timeoutu zapisu $T_"enq" = 10 "ms"$) i odrzucenia $38,3 %$ pakietów kierowanych do całkowicie sprawnych węzłów sieci.

=== Niedopasowanie przepływności interfejsów i zjawisko _Bufferbloat_

Interfejs przewodowy USB NCM charakteryzuje się przepływnością rzędu kilkudziesięciu Mb/s i generuje ruch o charakterze grupowym, podczas gdy efektywna przepustowość warstwy ESP-NOW po uwzględnieniu narzutu nagłówków i oczekiwania na ramki ACK wynosi $R_"eff" approx 580 "kb/s"$ (czas serializacji pakietu $1400 "B"$ wynosi $T_"ser" = 19,31 "ms"$).

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (left, right, right, right, right),
    inset: 6pt,
    stroke: 0.5pt + luma(160),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    [*Konfiguracja (`tx_q_len` / `wait_ms`)*], [*Goodput*], [*Straty*], [*Śr. opóźnienie*], [*Max opóźnienie*],
    [1. Mała kolejka ($q=8$, $t_w=2 "ms"$)], [$588,0 "kb/s"$], [$60,8 %$], [$159,89 "ms"$], [$406,35 "ms"$],
    [2. Średnia kolejka ($q=16$, $t_w=5 "ms"$)], [$607,0 "kb/s"$], [$59,6 %$], [$350,74 "ms"$], [$561,15 "ms"$],
    [3. Obecny sterownik ($q=32$, $t_w=10 "ms"$)], [$852,3 "kb/s"$], [$43,2 %$], [$1618,51 "ms"$], [$3096,00 "ms"$],
    [4. Duża kolejka ($q=64$, $t_w=10 "ms"$)], [$888,2 "kb/s"$], [$40,8 %$], [$2009,10 "ms"$], [$3579,75 "ms"$],
    [5. Obecny sterownik + duże serie ($B=40$)], [$1997,0 "kb/s"$], [$33,5 %$], [$3649,79 "ms"$], [$7140,15 "ms"$],
  ),
  caption: [Analiza zjawiska _bufferbloat_ na styku USB NCM oraz ESP-NOW (`sim_usb_espnow_bridge.jl`).]
)

Zwiększanie głębokości bufora FIFO z $q=8$ do $q=64$ skutkuje klasycznym zjawiskiem _bufferbloat_: opóźnienie maksymalne wzrasta z $406,35 "ms"$ do ponad $3,5 "s"$, co w przypadku protokołów wyższych warstw (np. TCP lub mechanizmów synchronizacji CRDT czasu rzeczywistego) wywoła lawinowe retransmisje z tytułu przekroczenia RTO.

*Uwaga metodologiczna do modelu `sim_usb_espnow_bridge.jl`:* W scenariuszach 3–5 wyliczony w symulacji _Goodput_ ($852,3 - 1997,0 "kb/s"$) przekracza fizyczną przepustowość kanału zdefiniowaną w stałej `ESPNOW_EFFECTIVE_KBPS = 580.0`. Wynika to z konstrukcji pętli przyjmującej pakiet w `sim_usb_espnow_bridge.jl`: warunek `elseif q_wait <= enqueue_wait_ms` oceniany jest dla wszystkich pakietów w serii względem tego samego elementu `queue[1]`, co pozwala na dopisanie do wektora `queue` liczby pakietów przekraczającej limit `tx_q_len`, a metryka `goodput_kbps` zlicza pakiety przyjęte do bufora, a nie pakiety faktycznie wysłane przez interfejs radiowy. Po skorygowaniu metryki do pakietów opuszczających kolejkę, przepustowość użyteczna asymptotycznie dąży do $580 "kb/s"$, natomiast gigantyczne opóźnienie ($> 3 - 7 "s"$) potwierdza niestabilność kolejki w stanie przeciążenia.

== Analiza podatności bezpieczeństwa i odporności na ataki celowe

=== Wrażliwość na zakłócenia RF oraz ataki odmowy usługi (DoS)

Ponieważ sterownik nie implementuje selektywnej retransmisji brakujących fragmentów, prawdopodobieństwo pomyślnego złożenia pakietu złożonego z $M=7$ fragmentów przy stopie błędów pakietowych kanału równej $"PER"$ wynosi:
$ P_"sukces" = (1 - "PER")^M = (1 - "PER")^7 $
Oznacza to, że już przy umiarkowanych zakłóceniach radiowych ($"PER" = 15 %$), teoretyczna szansa na dostarczenie całego pakietu MTU spada do $(0,85)^7 approx 32,06 %$ (strata $67,94 %$ w samym medium transmisyjnym).

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (left, right, right, right, center),
    inset: 6pt,
    stroke: 0.5pt + luma(160),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    [*Scenariusz testowy*], [*Goodput*], [*Straty całkowite*], [*Śr. opóźnienie*], [*Rozkład strat (Q / NoMem / Air)*],
    [1. Warunki idealne ($"PER"=1 %$)], [$1253,3 "kb/s"$], [$6,8 %$], [$5,44 "ms"$], [0 / 0 / 81],
    [2. Umiarkowane zakłócenia ($"PER"=15 %$)], [$384,2 "kb/s"$], [$71,4 %$], [$349,92 "ms"$], [258 / 0 / 565],
    [3. Silne zakłócenia ($"PER"=35 %$)], [$45,9 "kb/s"$], [$96,6 %$], [$1062,92 "ms"$], [555 / 0 / 487],
    [4. Lekki atak DoS ($800 "pps"$, $"PER"=5 %$)], [$219,5 "kb/s"$], [$83,7 %$], [$855,66 "ms"$], [436 / 0 / 464],
    [5. Silny atak DoS ($2200 "pps"$, $"PER"=5 %$)], [$6,7 "kb/s"$], [$99,5 %$], [$1913,25 "ms"$], [915 / 61 / 134],
  ),
  caption: [Wpływ stopy błędów PER oraz ataku zalewania ramkami na przepustowość (`sim_dos_jamming.jl`).]
)

Dodatkowym wektorem degradacji podczas ataku DoS jest obsługa błędu `ESP_ERR_ESPNOW_NO_MEM`. W przypadku wyczerpania wewnętrznych buforów DMA stosu Wi-Fi, zadanie nadawcze wykonuje do 20 prób ponowienia z opóźnieniem `vTaskDelay(1 ms)`. W warunkach silnego ataku ($2200 "pps"$) wydłuża to czas obsługi pojedynczego pakietu, prowadząc do odrzucenia 915 z 1200 wygenerowanych pakietów już na etapie przepełnionej kolejki wejściowej.

=== Podatności mechanizmu reasemblacji (`espnow_reasm_process_src`)

Analiza funkcji składania fragmentów w `sim_fragmentation_vuln.jl` ujawniła dwa krytyczne błędy bezpieczeństwa wynikające z braku uwierzytelniania ramek oraz statycznej alokacji zasobów:

1. Atak wywłaszczenia slotów: Pula buforów reasemblacji jest ograniczona do `REASM_SLOTS = 4` struktur po $1600 "B"$. W sytuacji, gdy wszystkie sloty są zajęte przez niekompletne pakiety, nadejście nowego fragmentu wymusza bezwarunkową eksmisję wpisu o najstarszym znaczniku czasu `last_tick` (polityka LRU). Napastnik wysyłający pojedyncze ramki inicjujące (`frag_idx = 0`, `frag_total = 2`, rozmiar $10 "B"$) z losowymi identyfikatorami `frame_id` jest w stanie wyczyścić wszystkie 4 sloty odbiorcy przed dotarciem ostatniego (szóstego) fragmentu legalnego pakietu (status `evicted_other`). Koszt przeprowadzenia ataku jest asymetryczny: wysłanie 4 ramek o łącznym rozmiarze $40 "B"$ niszczy pakiet o rozmiarze $1464 "B"$.
2. Zatruwanie ładunku: Identyfikacja sesji reasemblacji opiera się wyłącznie na nieszyfrowanej parze `(src_mac, frame_id)`, gdzie `s_tx_frame_id` jest przewidywalnym, liniowo inkrementowanym licznikiem 16-bitowym. Co więcej, implementacja nie weryfikuje, czy bit odpowiadający danemu `frag_idx` w masce `slot.mask` został już ustawiony, pozwalając na wielokrotne nadpisywanie tego samego obszaru pamięci `slot.buffer`. W symulacji napastnik podszywający się pod adres MAC nadawcy (`02:00:00:00:00:01`) wstrzyknął sfałszowany fragment `frag_idx = 1` o rozmiarze $244 "B"$, który został bezbłędnie połączony z legalnymi fragmentami `0` oraz `2` i przekazany w górę stosu TCP/IP.

=== Wyczerpanie tablicy sąsiadów (_MAC Flooding & Broadcast Fallback_)

Tablica routingu warstwy łącza `s_peers` przechowuje maksymalnie `ESPNOW_MAX_PEERS = 20` wpisów. Odebranie jakiejkolwiek ramki powoduje wywołanie funkcji aktualizującej tablicę (`peer_table_touch!`). Jeżeli tablica jest pełna, algorytm usuwa najstarszy wpis nieoznaczony flagą `is_static`.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, right, right),
    inset: 6pt,
    stroke: 0.5pt + luma(160),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    [*Scenariusz i natężenie ataku MAC Flood*], [*Liczba wywłaszczeń*], [*Ruch zdegradowany do Broadcast*],
    [1. Brak ataku (wpis dynamiczny)], [0], [$0,0 %$],
    [2. Słaby atak: $15 "pps"$ (wpis dynamiczny)], [5], [$35,3 %$],
    [3. Średni atak: $100 "pps"$ (wpis dynamiczny)], [5], [$90,4 %$],
    [4. Silny atak: $500 "pps"$ (wpis dynamiczny)], [5], [$98,0 %$],
    [5. Silny atak: $500 "pps"$ (`is_static = true`)], [0], [$0,0 %$],
  ),
  caption: [Skutki ataku _MAC Flooding_ na tablicę `s_peers` w oknie $10 "s"$ (`sim_peer_table_eviction.jl`).]
)

Gdy legalny węzeł zostanie wyparty z tablicy `s_peers`, funkcja `espnow_resolve_dest_mac` nie odnajduje odwzorowania adresu docelowego i przełącza transmisję w tryb awaryjny (_broadcast fallback_ — wysyłanie na adres `FF:FF:FF:FF:FF:FF`). Ponieważ legalny węzeł odświeża swoją obecność ramką `BEACON` jedynie co $2000 "ms"$ (5 razy w ciągu $10 "s"$ symulacji), już atak o natężeniu $15 "pps"$ (zapełnienie 20 slotów zajmuje wówczas $1,33 "s"$) powoduje, że przez $35,3 %$ czasu komunikacja odbywa się w trybie rozgłoszeniowym (pozbawionym potwierdzeń ACK i szyfrowania), a przy $500 "pps"$ degradacja sięga $98,0 %$.

=== Analiza kryptograficzna przestrzeni kluczy CCMP

Weryfikacja przeprowadzona w skrypcie `verify_ccmp_keyspace.jl` zestawia obecny stan sterownika (`peer.encrypt = false`, przestrzeń kluczy $|K| = 2^0 = 1$) z natywnym dla standardu IEEE 802.11i szyfrowaniem AES-128 w trybie CCMP (_Counter Mode with Cipher Block Chaining Message Authentication Code Protocol_) oraz teoretycznym profilem AES-256.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (left, right, right, right),
    inset: 6pt,
    stroke: 0.5pt + luma(160),
    fill: (x, y) => if y == 0 { luma(230) } else { none },
    [*Parametr bezpieczeństwa*], [*Obecny sterownik*], [*ESP-NOW CCMP (AES-128)*], [*Hipoteza AES-256 CCMP*],
    [Rozmiar przestrzeni kluczy $|K|$], [$2^0 = 1$], [$2^128 approx 3,40 times 10^38$], [$2^256 approx 1,16 times 10^77$],
    [Czas ataku _brute-force_ ($10^21 "op/s"$)], [$0 "s"$ (tekst jawny)], [$5,40 times 10^9 "lat"$], [$1,84 times 10^48 "lat"$],
    [Złożoność kwantowa (alg. Grovera)], [brak], [$2^64$ operacji], [$2^128$ operacji],
    [Min. energia (granica Landauera, $300 "K"$)], [$0 "J"$], [$4,89 times 10^20 "J"$], [$1,66 times 10^59 "J"$],
    [Prawdopodobieństwo sfałszowania MIC], [$1,0$ ($0 "bitów"$)], [$2^(-64) approx 5,42 times 10^(-20)$], [$2^(-128) approx 2,94 times 10^(-39)$],
    [Limit kolizji 48-bit Nonce ($P=50 %$)], [n/d], [$1,98 times 10^7$ ramek], [$1,98 times 10^7$ ramek],
  ),
  caption: [Porównanie parametrów kryptograficznych profili CCMP (`verify_ccmp_keyspace.jl`).]
)

Wdrożenie sprzętowego szyfrowania CCMP (AES-128) w układzie ESP32 gwarantuje pełną odporność na pasywny podsłuch oraz eliminuje podatność na wstrzykiwanie fragmentów dzięki 64-bitowemu kodowi integralności wiadomości MIC ($P_"forgery" = 5,42 times 10^(-20)$). Analiza ujawniła jednak trzy istotne ograniczenia architektoniczne w stosie ESP-IDF:
1. *Limit sprzętowych slotów kluczy:* Układ kryptograficzny Wi-Fi w ESP32 obsługuje maksymalnie *17 zaszyfrowanych węzłów* jednocześnie (wobec 20 węzłów w trybie nieszyfrowanym).
2. *Paradoks urodzinowy dla 48-bitowego licznika PN (Packet Number / Nonce):* Prawdopodobieństwo kolizji wartości Nonce osiąga próg $50 %$ po przesłaniu $q approx sqrt(2 ln(2) dot 2^48) approx 1,975 times 10^7$ ramek, co przy ciągłej transmisji z prędkością $200 "fps"$ następuje po około $27,4$ godzinach i wymusza implementację protokołu okresowej rotacji klucza sesyjnego LMK (_Local Master Key_).
3. *Brak szyfrowania ramek rozgłoszeniowych:* Specyfikacja ESP-NOW CCMP nie przewiduje szyfrowania ani uwierzytelniania ramek kierowanych na adres `FF:FF:FF:FF:FF:FF`. W konsekwencji samo ustawienie flagi `peer.encrypt = true` nie zabezpiecza ramek `BEACON` przed podszywaniem się (_spoofing_) i nie chroni tablicy `s_peers` przed atakiem wyczerpania zasobów, jeżeli ruch rozgłoszeniowy nie zostanie dodatkowo uwierzytelniony w warstwie aplikacji.

= Podsumowanie i wnioski końcowe

== Stopień realizacji założonych celów

Główny cel projektu, zaprojektowanie, implementacja oraz weryfikacja bezprzewodowej karty sieciowej P2P bazującej na protokole ESP-NOW, został w pełni zrealizowany. Opracowany system skutecznie zestawia dwukierunkowy tunel warstwy 3 (IPv4) pomiędzy dwoma komputerami klasy PC bez udziału zewnętrznej infrastruktury sieciowej (punktów dostępowych Wi-Fi czy routerów).

Z powodzeniem rozwiązano problem asymetrii sprzętowej wykorzystanych mikrokontrolerów:
- Dla układu *ESP32-S3*, wyposażonego w sprzętowy kontroler USB OTG, wdrożono w pełni bezobsługowy interfejs klasy CDC-NCM (Plug & Play) z wbudowanym mini-serwerem DHCP oraz obsługą Proxy ARP.
- Dla układu *ESP32-C3*, pozbawionego natywnego USB OTG, zaimplementowano lekki most szeregowy oparty na protokole SLIP (RFC 1055) działający na wbudowanym kontrolerze `USB-Serial/JTAG`.
- Wspólną logikę radiową, obejmującą dynamiczne wykrywanie sąsiadów (`Autodiscovery`), zarządzanie tablicą węzłów oraz wieloslotową fragmentację i reasemblację pakietów, wydzielone do niezależnego modułu `espnow_common`.

== Wnioski

Przeprowadzone testy obciążeniowe w ujęciu czarnej skrzynki (`iperf3`, `ping`), wsparte szczegółową analizą kodu źródłowego oraz symulacjami zdarzeniowymi w języku Julia, pozwoliły na sformułowanie czterech fundamentalnych wniosków dotyczących projektowania niskopoziomowych interfejsów sieciowych IoT:

1. Dominacja limitu PPS nad przepustowością bitową
W systemach opartych na synchronicznym wywoływaniu ramek zarządzających 802.11 przy domyślnej modulacji 1 Mbit/s głównym wąskim gardłem nie jest rozmiar przesyłanych danych, lecz narzut czasowy pojedynczej transakcji radiowej. Układ osiąga stabilną przepustowość bliską 500 kbit/s dla dużych datagramów (1400 B przy ~45 PPS), natomiast ulega gwałtownej degradacji przy zalewaniu małymi pakietami (64 B) oraz przy dwukierunkowym ruchu TCP.

2. Wrażliwość na zjawisko Bufferbloat i blokowanie HoL
Niedopasowanie prędkości interfejsu USB Full-Speed (12 Mbit/s) do możliwości kanału radiowego ESP-NOW (~580 kbit/s) przy dużych kolejkach systemowych (`txqueuelen`) i wewnętrznych kolejkach FreeRTOS prowadzi do narastania opóźnień RTT powyżej 700 ms (a w skrajnych scenariuszach symulacyjnych powyżej 3 s). Ponadto brak mechanizmu wczesnego przerywania transmisji dla uszkodzonych lub nieosiągalnych węzłów powoduje krytyczne blokowanie początku kolejki nadawczej.

3. Asymetria kosztów w bezpieczeństwie warstwy łącza
Przeprowadzone symulacje udowodniły, że brak kryptograficznego uwierzytelniania ramek na poziomie warstwy fragmentacji pozwala na przeprowadzenie wysoce asymetrycznych ataków odmowy usługi (np. wyparcie 4 slotów reasemblacji i zniszczenie pakietu 1464 B kosztem wysłania zaledwie 40 B sfałszowanych nagłówków lub zatrucie tablicy peerów degradujące ruch do nieszyfrowanego trybu _broadcast_).

4. *Niewystarczalność natywnego CCMP bez protokołu zarządzania kluczami:* Włączenie sprzętowego szyfrowania AES-128-CCMP w standardzie ESP-NOW zabezpiecza wprawdzie ruch _unicast_ przed podsłuchem i modyfikacją, jednak ze względu na brak ochrony ramek rozgłoszeniowych (`BEACON`), limit sprzętowych slotów kluczy oraz przechowywanie licznika pakietów (Nonce/PN) wyłącznie w pamięci ulotnej RAM, rozwiązanie to jest podatne na ataki powtórzeniowe (_replay attacks_) oraz ponowne użycie wektora inicjalizującego po restarcie zasilania.

== Ewentualne kierunki dalszego rozwoju

Aby przekształcić opracowany prototyp w rozwiązanie o klasie produkcyjnej, w kolejnych iteracjach projektu należy wdrożyć następujące usprawnienia:
- Migracja do ESP-NOW v2.0 i agregacja pakietów
Zwiększenie rozmiaru pojedynczej ramki radiowej do 1470 B całkowicie wyeliminuje narzut fragmentacji dla standardowego MTU, a łączne pakowanie wielu małych pakietów IP (np. potwierdzeń TCP ACK) do jednej ramki ESP-NOW radykalnie zwiększy wydajność PPS.
- Asynchroniczny potok TX i kontrola modulacji PHY
Zastąpienie pojedynczego semafora binarnego `espnow_tx_sem` semaforem zliczającym (wykorzystującym pełną pulę buforów DMA sterownika Wi-Fi) oraz podniesienie prędkości warstwy PHY do 12--24 Mbit/s (OFDM).
- Kryptografia w warstwie wyższej lub uzgadnianie kluczy sesyjnych
Wdrożenie lekkiego protokołu wymiany kluczy (np. w oparciu o krzywą eliptyczną X25519 i szyfr ChaCha20-Poly1305 / ASCON bezpośrednio w buforze pakietu IP) lub zestawienie na hostach tunelu WireGuard, co uniezależni bezpieczeństwo transmisji od ograniczeń sprzętowych warstwy 802.11 w mikrokontrolerach ESP32.

#bibliography("bibliography.bib", title: [Bibliografia], style: "ieee", full: true)

= Załączniki
Repozytorium Githuba z całym projektem w formacie zip.

https://github.com/tfo-dot/netcard