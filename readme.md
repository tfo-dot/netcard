# Netcard

To repozytorium opisuje kartę sieciową opartą na płytkach XIAO SEEED ESP32{C3, S3}.

# Instalacja esp-idf na Arch Linux:

```bash
sudo pacman -S --needed gcc git make flex bison gperf python cmake ninja ccache dfu-util libusb
sudo usermod -aG uucp $USER

git clone -b release/v6.1 --recursive https://github.com/espressif/esp-idf.git
cd ~/esp/esp-idf
./install.sh esp32s3,esp32c3

source esp-idf/export.sh

#w danym folderze: 
idf.py build flash
```

# Komendy którymi była testowana przepustowość

```bash
ping -c 100 -i 0.2 10.0.0.2 | tee 01_ping_baseline.txt
```

```bash
for rate in 50K 100K 150K 250K 500K 1M 2M; do
  echo "=== TEST UDP: $rate ===" | tee -a 02_udp_sweep.txt
  iperf3 -c 10.0.0.2 -u -b $rate -l 400 -t 5 --get-server-output >> 02_udp_sweep.txt
done
```

```bash
for size in 64 512 1400; do
  echo "=== TEST ROZMIAR: ${size}B ===" | tee -a 03_udp_packetsize.txt
  iperf3 -c 10.0.0.2 -u -b 500K -l $size -t 5 --get-server-output >> 03_udp_packetsize.txt
done
```

```bash
iperf3 -c 10.0.0.2 -V -i 0.5 -t 10 --get-server-output --logfile 04_tcp_verbose.txt
iperf3 -c 10.0.0.2 -i 0.5 -t 10 -J > 04_tcp_raw.json
```

```bash
{
  uname -a
  ip -s -d link show enp4s0f3u2
  ethtool -k enp4s0f3u2
  lsusb -t
} > 05_env_sender.txt
```

```bash
{
  uname -a
  ip -s -d link show sl0
  ethtool -k sl0
  lsusb -t
} > 05_env_receiver.txt
```

# Komenda żeby zrównać MTU interfejsów

sudo ip link set dev enp4s0f3u2 mtu 1400

# Opis skryptów

- `flash_s3.sh` - flashowanie bez importu esp-idf do powłoki (np. nushell)
- `setup_c3.sh` - ustanowienie połączenia przez SLIP korzystając z `ldattach`
- `stop_c3.sh` - wyłączenie komunikacji (interfejsu SL0) przez esp32c3