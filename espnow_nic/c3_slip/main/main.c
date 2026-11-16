#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "driver/usb_serial_jtag.h"
#include "espnow_common.h"

// --- Stałe protokołu SLIP (RFC 1055) ---
#define SLIP_END     0xC0
#define SLIP_ESC     0xDB
#define SLIP_ESC_END 0xDC
#define SLIP_ESC_ESC 0xDD

// Autodiscovery dynamically detects peer MAC addresses; no hardcoded MAC needed

static QueueHandle_t slip_tx_q = NULL;

// Task wysyłający pakiety SLIP do PC 2 przez USB-Serial/JTAG
static void slip_tx_task(void *arg) {
    pkt_item_t item;
    static uint8_t raw_buf[MAX_PACKET_SIZE * 2 + 2];

    while (1) {
        if (xQueueReceive(slip_tx_q, &item, portMAX_DELAY) == pdTRUE) {
            size_t pos = 0;
            raw_buf[pos++] = SLIP_END;
            for (size_t i = 0; i < item.len; i++) {
                if (item.data[i] == SLIP_END) {
                    raw_buf[pos++] = SLIP_ESC;
                    raw_buf[pos++] = SLIP_ESC_END;
                } else if (item.data[i] == SLIP_ESC) {
                    raw_buf[pos++] = SLIP_ESC;
                    raw_buf[pos++] = SLIP_ESC_ESC;
                } else {
                    raw_buf[pos++] = item.data[i];
                }
            }
            raw_buf[pos++] = SLIP_END;

            // Zapis z podziałem na mniejsze porcje w razie zapełnienia bufora pierścieniowego
            size_t sent = 0;
            while (sent < pos) {
                int w = usb_serial_jtag_write_bytes(raw_buf + sent, pos - sent, pdMS_TO_TICKS(10));
                if (w > 0) {
                    sent += w;
                } else {
                    break; // Jeśli host przestał czytać TTY, porzuć ramkę zamiast blokować całą kolejkę
                }
            }
        }
    }
}

static void on_espnow_recv(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
    pkt_item_t *pkt = NULL;
    if (espnow_reasm_process_src(NULL, info->src_addr, data, len, 0, &pkt)) {
        xQueueSend(slip_tx_q, pkt, pdMS_TO_TICKS(10));
    }
}
// Task wyłącznie dekodujący strumień SLIP z USB-Serial/JTAG (zero blokowania na Wi-Fi)
static void slip_rx_task(void *arg) {
    static pkt_item_t item;
    uint8_t usb_chunk[512];
    size_t pos = 0;
    bool escaped = false;

    while (1) {
        int r = usb_serial_jtag_read_bytes(usb_chunk, sizeof(usb_chunk), pdMS_TO_TICKS(10));
        if (r <= 0) continue;

        for (int i = 0; i < r; i++) {
            uint8_t byte = usb_chunk[i];

            if (byte == SLIP_END) {
                if (pos > 0) {
                    item.len = pos;
                    memset(item.dst_mac, 0, 6);
                    if (pos >= 20 && ((item.data[0] >> 4) == 4)) {
                        uint32_t src_ip;
                        memcpy(&src_ip, item.data + 12, 4);
                        if (src_ip != 0 && (espnow_get_local_ip() != src_ip)) {
                            espnow_set_local_ip(src_ip);
                        }
                    }
                    xQueueSend(espnow_tx_q, &item, pdMS_TO_TICKS(10));
                    pos = 0;
                }
                escaped = false;
            } else if (byte == SLIP_ESC) {
                escaped = true;
            } else {
                if (escaped) {
                    if (byte == SLIP_ESC_END) byte = SLIP_END;
                    else if (byte == SLIP_ESC_ESC) byte = SLIP_ESC;
                    escaped = false;
                }
                if (pos < MAX_PACKET_SIZE) {
                    item.data[pos++] = byte;
                } else {
                    // Ochrona przed przepełnieniem przy zgubionym bajcie SLIP_END
                    pos = 0;
                    escaped = false;
                }
            }
        }
    }
}

void app_main(void) {
    usb_serial_jtag_driver_config_t usb_cfg = {
        .tx_buffer_size = 16384,
        .rx_buffer_size = 16384,
    };
    ESP_ERROR_CHECK(usb_serial_jtag_driver_install(&usb_cfg));

    slip_tx_q = xQueueCreate(24, sizeof(pkt_item_t));

    ESP_ERROR_CHECK(espnow_common_init(NULL, 1, on_espnow_recv));

    xTaskCreate(slip_tx_task,   "slip_tx",   4096, NULL, 6, NULL);
    xTaskCreate(slip_rx_task,   "slip_rx",   4096, NULL, 6, NULL);
    xTaskCreate(espnow_tx_task, "espnow_tx", 4096, NULL, 5, NULL);
}
