#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "tinyusb.h"
#include "tinyusb_default_config.h"
#include "tinyusb_net.h"
#include "espnow_common.h"

// Autodiscovery dynamically detects peer MAC addresses; no hardcoded MAC needed
static uint8_t       host_mac[6]   = {0x02, 0x00, 0x00, 0x00, 0x00, 0x01};
static const uint8_t remote_mac[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0x02};

static QueueHandle_t usb_tx_q = NULL;

static void usb_tx_task(void *arg) {
    pkt_item_t item;
    while (1) {
        if (xQueueReceive(usb_tx_q, &item, portMAX_DELAY) == pdTRUE) {
            tinyusb_net_send_sync(item.data, item.len, NULL, pdMS_TO_TICKS(50));
        }
    }
}

static uint16_t ip_chksum(const void *data, size_t len) {
    const uint16_t *buf = (const uint16_t *)data;
    uint32_t sum = 0;
    while (len > 1) {
        sum += *buf++;
        len -= 2;
    }
    if (len == 1) {
        sum += *(const uint8_t *)buf;
    }
    while (sum >> 16) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    return (uint16_t)(~sum);
}

static bool handle_dhcp(const uint8_t *eth, uint16_t len) {
    if (len < 282) return false;
    const uint8_t *ip = eth + 14;
    if (ip[9] != 17) return false;
    const uint8_t *udp = ip + 20;
    uint16_t dst_port = ((uint16_t)udp[2] << 8) | udp[3];
    if (dst_port != 67) return false;

    const uint8_t *dhcp = udp + 8;
    if (dhcp[0] != 1) return false;
    if (memcmp(dhcp + 236, "\x63\x82\x53\x63", 4) != 0) return false;

    uint8_t msg_type = 0;
    size_t opt_idx = 240;
    size_t dhcp_len = len - 42;
    while (opt_idx < dhcp_len && dhcp[opt_idx] != 0xFF) {
        if (dhcp[opt_idx] == 0) { opt_idx++; continue; }
        if (opt_idx + 1 >= dhcp_len) break;
        uint8_t code = dhcp[opt_idx];
        uint8_t olen = dhcp[opt_idx + 1];
        if (opt_idx + 2 + olen > dhcp_len) break;
        if (code == 53 && olen == 1) {
            msg_type = dhcp[opt_idx + 2];
        }
        opt_idx += 2 + olen;
    }

    if (msg_type != 1 && msg_type != 3) return false;
    uint8_t reply_type = (msg_type == 1) ? 2 : 5;

    pkt_item_t reply;
    memset(&reply, 0, sizeof(reply));

    memcpy(reply.data, eth + 6, 6);
    memcpy(reply.data + 6, remote_mac, 6);
    reply.data[12] = 0x08; reply.data[13] = 0x00;

    uint8_t *rip = reply.data + 14;
    rip[0] = 0x45;
    rip[4] = 0x00; rip[5] = 0x01;
    rip[8] = 64;
    rip[9] = 17;
    rip[12] = 10; rip[13] = 0; rip[14] = 0; rip[15] = 2;
    rip[16] = 10; rip[17] = 0; rip[18] = 0; rip[19] = 1;

    uint8_t *rudp = reply.data + 34;
    rudp[0] = 0; rudp[1] = 67;
    rudp[2] = 0; rudp[3] = 68;

    uint8_t *rdhcp = reply.data + 42;
    rdhcp[0] = 2;
    rdhcp[1] = 1;
    rdhcp[2] = 6;
    memcpy(rdhcp + 4, dhcp + 4, 4);
    rdhcp[16] = 10; rdhcp[17] = 0; rdhcp[18] = 0; rdhcp[19] = 1;
    rdhcp[20] = 10; rdhcp[21] = 0; rdhcp[22] = 0; rdhcp[23] = 2;
    memcpy(rdhcp + 28, eth + 6, 6);
    memcpy(rdhcp + 236, "\x63\x82\x53\x63", 4);

    size_t ropt = 240;
    rdhcp[ropt++] = 53; rdhcp[ropt++] = 1; rdhcp[ropt++] = reply_type;
    rdhcp[ropt++] = 1;  rdhcp[ropt++] = 4;
    rdhcp[ropt++] = 255; rdhcp[ropt++] = 255; rdhcp[ropt++] = 255; rdhcp[ropt++] = 0;
    rdhcp[ropt++] = 3;  rdhcp[ropt++] = 4;
    rdhcp[ropt++] = 10; rdhcp[ropt++] = 0; rdhcp[ropt++] = 0; rdhcp[ropt++] = 2;
    rdhcp[ropt++] = 51; rdhcp[ropt++] = 4;
    rdhcp[ropt++] = 0x00; rdhcp[ropt++] = 0x01; rdhcp[ropt++] = 0x51; rdhcp[ropt++] = 0x80;
    rdhcp[ropt++] = 54; rdhcp[ropt++] = 4;
    rdhcp[ropt++] = 10; rdhcp[ropt++] = 0; rdhcp[ropt++] = 0; rdhcp[ropt++] = 2;
    rdhcp[ropt++] = 255;

    while (ropt < 300) { rdhcp[ropt++] = 0; }

    uint16_t udp_len = 8 + ropt;
    rudp[4] = (udp_len >> 8); rudp[5] = (udp_len & 0xFF);

    uint16_t ip_tot_len = 20 + udp_len;
    rip[2] = (ip_tot_len >> 8); rip[3] = (ip_tot_len & 0xFF);
    uint16_t csum = ip_chksum(rip, 20);
    rip[10] = (csum >> 8); rip[11] = (csum & 0xFF);

    reply.len = 14 + ip_tot_len;
    xQueueSend(usb_tx_q, &reply, 0);
    return true;
}

static esp_err_t usb_ncm_recv_cb(void *buffer, uint16_t len, void *ctx) {
    if (len < 14) return ESP_OK;
    const uint8_t *eth = (const uint8_t *)buffer;
    uint16_t ethertype = ((uint16_t)eth[12] << 8) | eth[13];

    memcpy(host_mac, eth + 6, 6);

    if (ethertype == 0x0806 && len >= 42) {
        // Do not reply to DAD probes for host's own IP (10.0.0.1)
        if (eth[38] == 10 && eth[39] == 0 && eth[40] == 0 && eth[41] == 1) {
            return ESP_OK;
        }
        pkt_item_t reply;
        reply.len = 42;
        memset(reply.dst_mac, 0, 6);
        memcpy(reply.data, eth + 6, 6);
        memcpy(reply.data + 6, remote_mac, 6);
        reply.data[12] = 0x08;
        reply.data[13] = 0x06;
        memcpy(reply.data + 14, eth + 14, 6);
        reply.data[20] = 0x00;
        reply.data[21] = 0x02;
        memcpy(reply.data + 22, remote_mac, 6);
        memcpy(reply.data + 28, eth + 38, 4);
        memcpy(reply.data + 32, eth + 22, 10);
        xQueueSend(usb_tx_q, &reply, 0);
        return ESP_OK;
    }
    if (ethertype == 0x0800 && handle_dhcp(eth, len)) {
        return ESP_OK;
    }

    if (ethertype == 0x0800) {
        uint16_t ip_len = len - 14;
        if (ip_len <= MAX_PACKET_SIZE) {
            pkt_item_t item;
            item.len = ip_len;
            memset(item.dst_mac, 0, 6);
            memcpy(item.data, eth + 14, ip_len);
            // Short timeout (2 ms) lets espnow_tx_task drain slots rather than dropping immediately
            xQueueSend(espnow_tx_q, &item, pdMS_TO_TICKS(10));
        }
    }

    return ESP_OK;
}

static void on_espnow_recv(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
    pkt_item_t *pkt = NULL;
    if (espnow_reasm_process_src(NULL, info->src_addr, data, len, 14, &pkt)) {
        memcpy(pkt->data, host_mac, 6);
        memcpy(pkt->data + 6, remote_mac, 6);
        pkt->data[12] = 0x08;
        pkt->data[13] = 0x00;
        xQueueSend(usb_tx_q, pkt, pdMS_TO_TICKS(10));
    }
}

void app_main(void) {
    usb_tx_q = xQueueCreate(32, sizeof(pkt_item_t));

    const tinyusb_config_t tusb_cfg = TINYUSB_DEFAULT_CONFIG();
    ESP_ERROR_CHECK(tinyusb_driver_install(&tusb_cfg));

    const tinyusb_net_config_t net_cfg = {
        .mac_addr = {0x02, 0x00, 0x00, 0x00, 0x00, 0x01},
        .on_recv_callback = usb_ncm_recv_cb,
        .free_tx_buffer = NULL,
        .user_context = NULL
    };
    ESP_ERROR_CHECK(tinyusb_net_init(&net_cfg));

    ESP_ERROR_CHECK(espnow_common_init(NULL, 1, on_espnow_recv));

    xTaskCreatePinnedToCore(espnow_tx_task, "espnow_tx", 4096, NULL, 6, NULL, 1);
    xTaskCreatePinnedToCore(usb_tx_task,    "usb_tx",    4096, NULL, 6, NULL, 1);
}
