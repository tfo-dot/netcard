#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#include "espnow_common.h"
#include "nvs_flash.h"
#include "esp_netif.h"
#include "esp_event.h"
#include "esp_wifi.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "esp_log.h"

static const char *TAG = "espnow_common";

QueueHandle_t espnow_tx_q = NULL;
SemaphoreHandle_t espnow_tx_sem = NULL;
static SemaphoreHandle_t s_tx_mutex = NULL;

static uint16_t s_tx_frame_id = 0;
static const uint8_t s_broadcast_mac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
static uint8_t s_local_mac[6] = {0};
static uint8_t s_channel = 1;

static espnow_node_type_t s_local_node_type = ESPNOW_NODE_UNKNOWN;
static uint32_t s_local_ip = 0;
static esp_now_recv_cb_t s_user_recv_cb = NULL;

static TaskHandle_t s_disc_task_handle = NULL;
static uint8_t s_resp_target_mac[6] = {0};
static volatile bool s_need_send_resp = false;

// Peer table
#define ESPNOW_PEER_TIMEOUT_TICKS pdMS_TO_TICKS(ESPNOW_PEER_TIMEOUT_MS)
#define ESPNOW_BEACON_INTERVAL_MS 2000

static espnow_peer_entry_t s_peers[ESPNOW_MAX_PEERS];
static portMUX_TYPE s_peer_lock = portMUX_INITIALIZER_UNLOCKED;

// Reassembly slots
static reasm_slot_t s_default_rx_slots[REASM_SLOTS];

// Static helpers
static inline bool espnow_is_broadcast_mac(const uint8_t *mac) {
    return mac && mac[0] == 0xFF && mac[1] == 0xFF && mac[2] == 0xFF &&
           mac[3] == 0xFF && mac[4] == 0xFF && mac[5] == 0xFF;
}

static inline bool espnow_is_zero_mac(const uint8_t *mac) {
    if (!mac) return true;
    return (mac[0] | mac[1] | mac[2] | mac[3] | mac[4] | mac[5]) == 0;
}

static inline bool espnow_is_ip_broadcast(uint32_t ip) {
    if (ip == 0 || ip == 0xFFFFFFFF) return true;
    uint8_t last_octet = (ip >> 24) & 0xFF;
    if (last_octet == 255) return true;
    uint8_t first_octet = (ip >> 0) & 0xFF;
    if (first_octet >= 224 && first_octet <= 239) return true;
    return false;
}

void on_espnow_send(const wifi_tx_info_t *mac_addr, esp_now_send_status_t status) {
    if (espnow_tx_sem) {
        BaseType_t hp_task_woken = pdFALSE;
        xSemaphoreGiveFromISR(espnow_tx_sem, &hp_task_woken);
        if (hp_task_woken) {
            portYIELD_FROM_ISR();
        }
    }
}

esp_err_t espnow_common_nvs_init(void) {
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ret = nvs_flash_erase();
        if (ret != ESP_OK) {
            return ret;
        }
        ret = nvs_flash_init();
    }
    return ret;
}

esp_err_t espnow_common_wifi_init(uint8_t channel) {
    esp_err_t ret = esp_netif_init();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        return ret;
    }

    ret = esp_event_loop_create_default();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        return ret;
    }

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ret = esp_wifi_init(&cfg);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        return ret;
    }

    ret = esp_wifi_set_storage(WIFI_STORAGE_RAM);
    if (ret != ESP_OK) return ret;

    ret = esp_wifi_set_mode(WIFI_MODE_STA);
    if (ret != ESP_OK) return ret;

    ret = esp_wifi_start();
    if (ret != ESP_OK) return ret;

    ret = esp_wifi_set_channel(channel, WIFI_SECOND_CHAN_NONE);
    if (ret != ESP_OK) return ret;

    ret = esp_wifi_set_ps(WIFI_PS_NONE);
    if (ret != ESP_OK) return ret;

    return ESP_OK;
}

const uint8_t *espnow_get_local_mac(void) {
    return s_local_mac;
}

void espnow_set_local_ip(uint32_t ip) {
    s_local_ip = ip;
}

uint32_t espnow_get_local_ip(void) {
    return s_local_ip;
}

void espnow_set_local_node_type(espnow_node_type_t type) {
    s_local_node_type = type;
}

void espnow_set_peer_mac(const uint8_t *peer_mac) {
    if (peer_mac && !espnow_is_broadcast_mac(peer_mac) && !espnow_is_zero_mac(peer_mac)) {
        espnow_peer_table_add(peer_mac, 0, ESPNOW_NODE_UNKNOWN, true);
    }
}

const uint8_t *espnow_get_peer_mac(void) {
    static uint8_t first_mac[6];
    if (espnow_peer_table_get_first(first_mac) == ESP_OK) {
        return first_mac;
    }
    return s_broadcast_mac;
}

esp_err_t espnow_add_or_update_peer(const uint8_t *peer_mac, uint8_t channel) {
    if (!peer_mac) {
        return ESP_ERR_INVALID_ARG;
    }
    esp_now_peer_info_t peer = {0};
    memcpy(peer.peer_addr, peer_mac, 6);
    peer.channel = channel;
    peer.ifidx = WIFI_IF_STA;
    peer.encrypt = false;

    if (esp_now_is_peer_exist(peer_mac)) {
        return esp_now_mod_peer(&peer);
    }
    return esp_now_add_peer(&peer);
}

// --- Peer Table Management ---

static void espnow_peer_table_init(void) {
    taskENTER_CRITICAL(&s_peer_lock);
    for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
        memset(&s_peers[i], 0, sizeof(espnow_peer_entry_t));
    }
    taskEXIT_CRITICAL(&s_peer_lock);
}

esp_err_t espnow_peer_table_add(const uint8_t *mac, uint32_t ip, espnow_node_type_t type, bool is_static) {
    if (!mac || espnow_is_broadcast_mac(mac) || espnow_is_zero_mac(mac)) {
        return ESP_ERR_INVALID_ARG;
    }
    if (memcmp(mac, s_local_mac, 6) == 0) {
        return ESP_ERR_INVALID_ARG;
    }

    uint32_t now = (uint32_t)xTaskGetTickCount();
    bool added_new = false;
    uint8_t evicted_mac[6] = {0};
    bool need_evict = false;

    taskENTER_CRITICAL(&s_peer_lock);
    int found_idx = -1;
    for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
        if (s_peers[i].active && memcmp(s_peers[i].mac, mac, 6) == 0) {
            found_idx = i;
            break;
        }
    }

    if (found_idx >= 0) {
        s_peers[found_idx].last_seen = now;
        if (ip != 0) {
            s_peers[found_idx].ip = ip;
        }
        if (type != ESPNOW_NODE_UNKNOWN) {
            s_peers[found_idx].node_type = type;
        }
        if (is_static) {
            s_peers[found_idx].is_static = true;
        }
    } else {
        int free_idx = -1;
        for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
            if (!s_peers[i].active) {
                free_idx = i;
                break;
            }
        }

        if (free_idx < 0) {
            uint32_t oldest_tick = UINT32_MAX;
            for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
                if (!s_peers[i].is_static && s_peers[i].last_seen < oldest_tick) {
                    oldest_tick = s_peers[i].last_seen;
                    free_idx = i;
                }
            }
            if (free_idx >= 0) {
                memcpy(evicted_mac, s_peers[free_idx].mac, 6);
                need_evict = true;
            }
        }

        if (free_idx >= 0) {
            memcpy(s_peers[free_idx].mac, mac, 6);
            s_peers[free_idx].ip = ip;
            s_peers[free_idx].node_type = type;
            s_peers[free_idx].last_seen = now;
            s_peers[free_idx].active = true;
            s_peers[free_idx].is_static = is_static;
            added_new = true;
        }
    }
    taskEXIT_CRITICAL(&s_peer_lock);

    if (need_evict) {
        ESP_LOGW(TAG, "Evicting old peer " MACSTR, MAC2STR(evicted_mac));
        esp_now_del_peer(evicted_mac);
    }

    if (added_new || !esp_now_is_peer_exist(mac)) {
        esp_err_t err = espnow_add_or_update_peer(mac, s_channel);
        if (err == ESP_OK) {
            ESP_LOGI(TAG, "Added peer " MACSTR " (type: %d, IP: " ESPNOW_IP_STR ")",
                     MAC2STR(mac), type, ESPNOW_IP_ARG(ip));
        } else {
            ESP_LOGE(TAG, "Failed to add ESP-NOW peer " MACSTR ": %s",
                     MAC2STR(mac), esp_err_to_name(err));
            return err;
        }
    }

    return ESP_OK;
}

static void espnow_peer_table_touch(const uint8_t *mac) {
    if (!mac || espnow_is_broadcast_mac(mac) || espnow_is_zero_mac(mac)) return;
    if (memcmp(mac, s_local_mac, 6) == 0) return;

    bool found = false;
    uint32_t now = (uint32_t)xTaskGetTickCount();

    taskENTER_CRITICAL(&s_peer_lock);
    for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
        if (s_peers[i].active && memcmp(s_peers[i].mac, mac, 6) == 0) {
            s_peers[i].last_seen = now;
            found = true;
            break;
        }
    }
    taskEXIT_CRITICAL(&s_peer_lock);

    if (!found) {
        espnow_peer_table_add(mac, 0, ESPNOW_NODE_UNKNOWN, false);
    }
}

void espnow_peer_table_update_ip(const uint8_t *mac, uint32_t ip) {
    if (!mac || ip == 0 || espnow_is_broadcast_mac(mac) || espnow_is_ip_broadcast(ip)) return;
    if (memcmp(mac, s_local_mac, 6) == 0) return;

    taskENTER_CRITICAL(&s_peer_lock);
    for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
        if (s_peers[i].active && memcmp(s_peers[i].mac, mac, 6) == 0) {
            if (s_peers[i].ip != ip) {
                s_peers[i].ip = ip;
                ESP_LOGI(TAG, "Updated peer " MACSTR " IP to " ESPNOW_IP_STR,
                         MAC2STR(mac), ESPNOW_IP_ARG(ip));
            }
            s_peers[i].last_seen = (uint32_t)xTaskGetTickCount();
            break;
        }
    }
    taskEXIT_CRITICAL(&s_peer_lock);
}

esp_err_t espnow_peer_table_find_by_ip(uint32_t ip, uint8_t *out_mac) {
    if (ip == 0 || !out_mac) return ESP_ERR_INVALID_ARG;

    esp_err_t ret = ESP_ERR_NOT_FOUND;
    taskENTER_CRITICAL(&s_peer_lock);
    for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
        if (s_peers[i].active && s_peers[i].ip == ip) {
            memcpy(out_mac, s_peers[i].mac, 6);
            ret = ESP_OK;
            break;
        }
    }
    taskEXIT_CRITICAL(&s_peer_lock);
    return ret;
}

size_t espnow_peer_table_count(void) {
    size_t count = 0;
    taskENTER_CRITICAL(&s_peer_lock);
    for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
        if (s_peers[i].active) count++;
    }
    taskEXIT_CRITICAL(&s_peer_lock);
    return count;
}

esp_err_t espnow_peer_table_get_first(uint8_t *out_mac) {
    if (!out_mac) return ESP_ERR_INVALID_ARG;
    esp_err_t ret = ESP_ERR_NOT_FOUND;
    taskENTER_CRITICAL(&s_peer_lock);
    for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
        if (s_peers[i].active) {
            memcpy(out_mac, s_peers[i].mac, 6);
            ret = ESP_OK;
            break;
        }
    }
    taskEXIT_CRITICAL(&s_peer_lock);
    return ret;
}

size_t espnow_peer_table_get_all(espnow_peer_entry_t *out_peers, size_t max_peers) {
    if (!out_peers || max_peers == 0) return 0;
    size_t count = 0;
    taskENTER_CRITICAL(&s_peer_lock);
    for (int i = 0; i < ESPNOW_MAX_PEERS && count < max_peers; i++) {
        if (s_peers[i].active) {
            memcpy(&out_peers[count++], &s_peers[i], sizeof(espnow_peer_entry_t));
        }
    }
    taskEXIT_CRITICAL(&s_peer_lock);
    return count;
}

void espnow_peers_age_check(void) {
    uint32_t now = (uint32_t)xTaskGetTickCount();
    uint8_t timeout_macs[ESPNOW_MAX_PEERS][6];
    size_t timeout_count = 0;

    taskENTER_CRITICAL(&s_peer_lock);
    for (int i = 0; i < ESPNOW_MAX_PEERS; i++) {
        if (s_peers[i].active && !s_peers[i].is_static) {
            if ((now - s_peers[i].last_seen) > ESPNOW_PEER_TIMEOUT_TICKS) {
                memcpy(timeout_macs[timeout_count++], s_peers[i].mac, 6);
                s_peers[i].active = false;
                s_peers[i].ip = 0;
            }
        }
    }
    taskEXIT_CRITICAL(&s_peer_lock);

    for (size_t i = 0; i < timeout_count; i++) {
        ESP_LOGW(TAG, "Peer timed out: " MACSTR, MAC2STR(timeout_macs[i]));
        esp_now_del_peer(timeout_macs[i]);
    }
}

esp_err_t espnow_resolve_dest_mac(const uint8_t *data, size_t len, uint8_t *out_mac) {
    if (!out_mac) return ESP_ERR_INVALID_ARG;

    memcpy(out_mac, s_broadcast_mac, 6);

    if (data && len >= 20 && ((data[0] >> 4) == 4)) {
        uint32_t dst_ip;
        memcpy(&dst_ip, data + 16, 4);

        if (espnow_is_ip_broadcast(dst_ip)) {
            return ESP_OK;
        }

        if (espnow_peer_table_find_by_ip(dst_ip, out_mac) == ESP_OK) {
            return ESP_OK;
        }
    }

    if (espnow_peer_table_count() == 1) {
        if (espnow_peer_table_get_first(out_mac) == ESP_OK) {
            return ESP_OK;
        }
    }

    memcpy(out_mac, s_broadcast_mac, 6);
    return ESP_OK;
}

// --- Discovery Packet Handlers & Task ---

esp_err_t espnow_send_discovery_beacon(void) {
    espnow_discovery_pkt_t pkt = {
        .magic = ESPNOW_DISCOV_MAGIC,
        .msg_type = ESPNOW_DISCOV_TYPE_BEACON,
        .node_type = (uint8_t)s_local_node_type,
        .ip = s_local_ip,
        .uptime_s = (uint32_t)(esp_timer_get_time() / 1000000ULL),
    };
    memcpy(pkt.sender_mac, s_local_mac, 6);

    if (s_tx_mutex) {
        xSemaphoreTake(s_tx_mutex, portMAX_DELAY);
    }
    if (espnow_tx_sem) {
        xSemaphoreTake(espnow_tx_sem, 0);
    }
    esp_err_t err = esp_now_send(s_broadcast_mac, (const uint8_t *)&pkt, sizeof(pkt));
    if (err == ESP_OK && espnow_tx_sem) {
        xSemaphoreTake(espnow_tx_sem, pdMS_TO_TICKS(15));
    }
    if (s_tx_mutex) {
        xSemaphoreGive(s_tx_mutex);
    }
    return err;
}

static esp_err_t espnow_send_discovery_response(const uint8_t *target_mac) {
    if (!target_mac || espnow_is_broadcast_mac(target_mac) || espnow_is_zero_mac(target_mac)) {
        return ESP_ERR_INVALID_ARG;
    }
    espnow_discovery_pkt_t pkt = {
        .magic = ESPNOW_DISCOV_MAGIC,
        .msg_type = ESPNOW_DISCOV_TYPE_RESPONSE,
        .node_type = (uint8_t)s_local_node_type,
        .ip = s_local_ip,
        .uptime_s = (uint32_t)(esp_timer_get_time() / 1000000ULL),
    };
    memcpy(pkt.sender_mac, s_local_mac, 6);

    if (s_tx_mutex) {
        xSemaphoreTake(s_tx_mutex, portMAX_DELAY);
    }
    if (espnow_tx_sem) {
        xSemaphoreTake(espnow_tx_sem, 0);
    }
    esp_err_t err = esp_now_send(target_mac, (const uint8_t *)&pkt, sizeof(pkt));
    if (err == ESP_OK && espnow_tx_sem) {
        xSemaphoreTake(espnow_tx_sem, pdMS_TO_TICKS(15));
    }
    if (s_tx_mutex) {
        xSemaphoreGive(s_tx_mutex);
    }
    return err;
}

static void espnow_handle_discovery_pkt(const esp_now_recv_info_t *info, const espnow_discovery_pkt_t *disc) {
    if (!info || !disc) return;
    if (memcmp(info->src_addr, s_local_mac, 6) == 0) return;

    espnow_peer_table_add(info->src_addr, disc->ip, (espnow_node_type_t)disc->node_type, false);

    if (disc->msg_type == ESPNOW_DISCOV_TYPE_BEACON) {
        memcpy(s_resp_target_mac, info->src_addr, 6);
        s_need_send_resp = true;
        if (s_disc_task_handle) {
            xTaskNotifyGive(s_disc_task_handle);
        }
    }
}

static void espnow_discovery_task(void *arg) {
    // Initial rapid burst on boot
    for (int i = 0; i < 3; i++) {
        espnow_send_discovery_beacon();
        vTaskDelay(pdMS_TO_TICKS(200));
    }

    while (1) {
        uint32_t notified = ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(ESPNOW_BEACON_INTERVAL_MS));
        if (notified > 0 || s_need_send_resp) {
            if (s_need_send_resp) {
                s_need_send_resp = false;
                uint8_t target[6];
                memcpy(target, s_resp_target_mac, 6);
                espnow_send_discovery_response(target);
            }
        } else {
            espnow_send_discovery_beacon();
            espnow_peers_age_check();
        }
    }
}

static void s_espnow_internal_recv_cb(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
    if (!info || !data || len <= 0) return;

    if (len == (int)sizeof(espnow_discovery_pkt_t)) {
        const espnow_discovery_pkt_t *disc = (const espnow_discovery_pkt_t *)data;
        if (disc->magic == ESPNOW_DISCOV_MAGIC) {
            espnow_handle_discovery_pkt(info, disc);
            return;
        }
    }

    espnow_peer_table_touch(info->src_addr);

    if (s_user_recv_cb) {
        s_user_recv_cb(info, data, len);
    }
}

esp_err_t espnow_discovery_start(espnow_node_type_t node_type, uint32_t local_ip, uint8_t channel) {
    s_local_node_type = node_type;
    if (local_ip != 0) {
        s_local_ip = local_ip;
    }
    s_channel = channel;
    if (!s_disc_task_handle) {
        BaseType_t res = xTaskCreate(espnow_discovery_task, "espnow_disc", 3072, NULL, 3, &s_disc_task_handle);
        return (res == pdPASS) ? ESP_OK : ESP_FAIL;
    }
    return ESP_OK;
}

// --- Reassembly Implementation ---

void espnow_reasm_init(reasm_slot_t *slots) {
    reasm_slot_t *target = slots ? slots : s_default_rx_slots;
    for (int i = 0; i < REASM_SLOTS; i++) {
        memset(target[i].src_mac, 0, 6);
        target[i].fid = 0xFFFF;
        target[i].mask = 0;
        target[i].active = 0;
        target[i].total_len = 0;
        target[i].last_tick = 0;
    }
}

bool espnow_reasm_process_src(reasm_slot_t *slots, const uint8_t *src_mac, const uint8_t *data, int len, size_t header_offset, pkt_item_t **out_pkt) {
    if (!data || len < (int)sizeof(frag_hdr_t)) {
        return false;
    }
    const espnow_frag_pkt_t *pkt = (const espnow_frag_pkt_t *)data;

    if (pkt->hdr.frag_idx >= 7 || pkt->hdr.frag_total == 0 || pkt->hdr.frag_total > 7 || pkt->hdr.payload_len > MAX_FRAG_PAYLOAD) {
        return false;
    }

    reasm_slot_t *target = slots ? slots : s_default_rx_slots;
    reasm_slot_t *slot = NULL;
    uint32_t now = (uint32_t)xTaskGetTickCount();

    // 1. Find matching active slot
    for (int i = 0; i < REASM_SLOTS; i++) {
        if (target[i].active && target[i].fid == pkt->hdr.frame_id) {
            if (!src_mac || memcmp(target[i].src_mac, src_mac, 6) == 0) {
                slot = &target[i];
                break;
            }
        }
    }

    // 2. If no matching slot found, allocate empty or oldest slot
    if (!slot) {
        int best_idx = -1;
        uint32_t oldest_tick = UINT32_MAX;
        for (int i = 0; i < REASM_SLOTS; i++) {
            if (!target[i].active || target[i].mask == 0) {
                best_idx = i;
                break;
            }
            if (target[i].last_tick < oldest_tick) {
                oldest_tick = target[i].last_tick;
                best_idx = i;
            }
        }
        if (best_idx < 0) best_idx = 0;
        slot = &target[best_idx];
        slot->active = 1;
        slot->fid = pkt->hdr.frame_id;
        slot->mask = 0;
        slot->total_len = 0;
        if (src_mac) {
            memcpy(slot->src_mac, src_mac, 6);
            memcpy(slot->pkt.src_mac, src_mac, 6);
        } else {
            memset(slot->src_mac, 0, 6);
            memset(slot->pkt.src_mac, 0, 6);
        }
    }

    slot->last_tick = now;

    uint16_t offset = pkt->hdr.frag_idx * MAX_FRAG_PAYLOAD;
    if (header_offset + offset + pkt->hdr.payload_len <= MAX_PACKET_SIZE) {
        memcpy(slot->pkt.data + header_offset + offset, pkt->data, pkt->hdr.payload_len);
        slot->mask |= (1U << pkt->hdr.frag_idx);
        if (pkt->hdr.frag_idx == pkt->hdr.frag_total - 1) {
            slot->total_len = offset + pkt->hdr.payload_len;
        }
    }

    uint8_t expected_mask = (1U << pkt->hdr.frag_total) - 1U;
    if (slot->mask == expected_mask && slot->total_len > 0) {
        slot->pkt.len = slot->total_len + header_offset;
        slot->active = 0;
        slot->mask = 0;
        slot->total_len = 0;

        if (src_mac) {
            memcpy(slot->pkt.src_mac, src_mac, 6);
        }

        // Auto-learn peer IP from completed IPv4 payload
        const uint8_t *ip_hdr = slot->pkt.data + header_offset;
        uint16_t ip_len = slot->pkt.len - header_offset;
        if (ip_len >= 20 && ((ip_hdr[0] >> 4) == 4) && src_mac) {
            uint32_t src_ip;
            memcpy(&src_ip, ip_hdr + 12, 4);
            espnow_peer_table_update_ip(src_mac, src_ip);
        }

        if (out_pkt) {
            *out_pkt = &slot->pkt;
        }
        return true;
    }
    return false;
}

bool espnow_reasm_process(reasm_slot_t *slots, const uint8_t *data, int len, size_t header_offset, pkt_item_t **out_pkt) {
    return espnow_reasm_process_src(slots, NULL, data, len, header_offset, out_pkt);
}

// --- Transmission Implementation ---

esp_err_t espnow_send_packet(const uint8_t *peer_mac, const uint8_t *data, size_t len) {
    if (!data || len == 0 || len > MAX_PACKET_SIZE) {
        return ESP_ERR_INVALID_ARG;
    }

    uint8_t target_mac[6];
    if (peer_mac && !espnow_is_zero_mac(peer_mac)) {
        memcpy(target_mac, peer_mac, 6);
    } else {
        espnow_resolve_dest_mac(data, len, target_mac);
    }

    uint8_t total = (len + MAX_FRAG_PAYLOAD - 1) / MAX_FRAG_PAYLOAD;
    uint16_t fid = __atomic_fetch_add(&s_tx_frame_id, 1, __ATOMIC_RELAXED);

    if (s_tx_mutex) {
        xSemaphoreTake(s_tx_mutex, portMAX_DELAY);
    }

    for (uint8_t i = 0; i < total; i++) {
        espnow_frag_pkt_t pkt;
        uint16_t offset = i * MAX_FRAG_PAYLOAD;
        uint16_t chunk = (len - offset > MAX_FRAG_PAYLOAD) ? MAX_FRAG_PAYLOAD : (len - offset);

        pkt.hdr.frame_id = fid;
        pkt.hdr.frag_idx = i;
        pkt.hdr.frag_total = total;
        pkt.hdr.payload_len = chunk;
        memcpy(pkt.data, data + offset, chunk);

        if (espnow_tx_sem) {
            xSemaphoreTake(espnow_tx_sem, 0);
        }
        esp_err_t err;
        int retries = 20;
        while ((err = esp_now_send(target_mac, (const uint8_t *)&pkt, sizeof(frag_hdr_t) + chunk)) == ESP_ERR_ESPNOW_NO_MEM && --retries > 0) {
            vTaskDelay(pdMS_TO_TICKS(1));
        }
        if (err == ESP_OK) {
            if (espnow_tx_sem) {
                xSemaphoreTake(espnow_tx_sem, pdMS_TO_TICKS(15));
            }
        } else {
            if (s_tx_mutex) {
                xSemaphoreGive(s_tx_mutex);
            }
            return err;
        }
    }

    if (s_tx_mutex) {
        xSemaphoreGive(s_tx_mutex);
    }
    return ESP_OK;
}

esp_err_t espnow_enqueue_packet_to(const uint8_t *dst_mac, const void *data, uint16_t len, TickType_t wait_ticks) {
    if (!espnow_tx_q || !data || len == 0 || len > MAX_PACKET_SIZE) {
        return ESP_ERR_INVALID_ARG;
    }
    pkt_item_t item;
    memset(&item, 0, sizeof(item));
    if (dst_mac) {
        memcpy(item.dst_mac, dst_mac, 6);
    }
    item.len = len;
    memcpy(item.data, data, len);
    if (xQueueSend(espnow_tx_q, &item, wait_ticks) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    return ESP_OK;
}

esp_err_t espnow_enqueue_packet(const void *data, uint16_t len, TickType_t wait_ticks) {
    return espnow_enqueue_packet_to(NULL, data, len, wait_ticks);
}

void espnow_tx_task(void *arg) {
    pkt_item_t item;
    while (1) {
        if (xQueueReceive(espnow_tx_q, &item, portMAX_DELAY) == pdTRUE) {
            const uint8_t *dest = espnow_is_zero_mac(item.dst_mac) ? NULL : item.dst_mac;
            espnow_send_packet(dest, item.data, item.len);
        }
    }
}

esp_err_t espnow_start_tx_task(UBaseType_t priority, BaseType_t core_id) {
    BaseType_t res;
    if (core_id == tskNO_AFFINITY) {
        res = xTaskCreate(espnow_tx_task, "espnow_tx", 4096, NULL, priority, NULL);
    } else {
        res = xTaskCreatePinnedToCore(espnow_tx_task, "espnow_tx", 4096, NULL, priority, NULL, core_id);
    }
    return (res == pdPASS) ? ESP_OK : ESP_FAIL;
}

esp_err_t espnow_common_init_custom(const uint8_t *peer_mac, uint8_t channel, esp_now_recv_cb_t recv_cb, size_t tx_q_len) {
    esp_err_t ret = espnow_common_nvs_init();
    if (ret != ESP_OK) return ret;

    s_channel = channel;

    ret = espnow_common_wifi_init(channel);
    if (ret != ESP_OK) return ret;

    ret = esp_wifi_get_mac(WIFI_IF_STA, s_local_mac);
    if (ret != ESP_OK) return ret;

    ESP_LOGI(TAG, "Local Wi-Fi STA MAC: " MACSTR " on channel %u", MAC2STR(s_local_mac), channel);

    if (!s_tx_mutex) {
        s_tx_mutex = xSemaphoreCreateMutex();
        if (!s_tx_mutex) return ESP_ERR_NO_MEM;
    }

    if (!espnow_tx_sem) {
        espnow_tx_sem = xSemaphoreCreateBinary();
        if (!espnow_tx_sem) return ESP_ERR_NO_MEM;
    }

    if (!espnow_tx_q) {
        espnow_tx_q = xQueueCreate(tx_q_len, sizeof(pkt_item_t));
        if (!espnow_tx_q) return ESP_ERR_NO_MEM;
    }

    espnow_reasm_init(NULL);
    espnow_peer_table_init();

    ret = esp_now_init();
    if (ret != ESP_OK) return ret;

    ret = esp_now_register_send_cb(on_espnow_send);
    if (ret != ESP_OK) return ret;

    s_user_recv_cb = recv_cb;
    ret = esp_now_register_recv_cb(s_espnow_internal_recv_cb);
    if (ret != ESP_OK) return ret;

    // Register broadcast peer so beacons and broadcast packets work immediately
    ret = espnow_add_or_update_peer(s_broadcast_mac, channel);
    if (ret != ESP_OK) return ret;

    // If static peer_mac is given and not broadcast, register it
    if (peer_mac && !espnow_is_broadcast_mac(peer_mac) && !espnow_is_zero_mac(peer_mac)) {
        espnow_peer_table_add(peer_mac, 0, ESPNOW_NODE_UNKNOWN, true);
    }

    // Default node type & IP based on chip target
#if CONFIG_IDF_TARGET_ESP32S3
    if (s_local_node_type == ESPNOW_NODE_UNKNOWN) {
        s_local_node_type = ESPNOW_NODE_S3_NCM;
    }
    if (s_local_ip == 0) {
        s_local_ip = ESPNOW_IPV4_ADDR(10, 0, 0, 1);
    }
#elif CONFIG_IDF_TARGET_ESP32C3
    if (s_local_node_type == ESPNOW_NODE_UNKNOWN) {
        s_local_node_type = ESPNOW_NODE_C3_SLIP;
    }
    if (s_local_ip == 0) {
        s_local_ip = ESPNOW_IPV4_ADDR(10, 0, 0, 2);
    }
#endif

    // Start background discovery task
    if (!s_disc_task_handle) {
        BaseType_t res = xTaskCreate(espnow_discovery_task, "espnow_disc", 3072, NULL, 3, &s_disc_task_handle);
        if (res != pdPASS) {
            ESP_LOGW(TAG, "Failed to create discovery task");
        }
    }

    return ESP_OK;
}

esp_err_t espnow_common_init(const uint8_t *peer_mac, uint8_t channel, esp_now_recv_cb_t recv_cb) {
    return espnow_common_init_custom(peer_mac, channel, recv_cb, 32);
}
