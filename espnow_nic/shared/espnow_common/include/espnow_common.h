#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "esp_err.h"
#include "esp_now.h"
#include "esp_wifi_types.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#ifdef __cplusplus
extern "C" {
#endif

// --- ESP-NOW Fragmentation & Packet Protocol Constants ---
#define MAX_FRAG_PAYLOAD 244
#define MAX_PACKET_SIZE  1600
#define REASM_SLOTS      8
#define ESPNOW_MAX_PEERS 16
#define ESPNOW_PEER_TIMEOUT_MS 30000
#define ESPNOW_DISCOV_MAGIC 0x4E494344 // 'NICD'
// --- Node Types & Discovery Constants ---
typedef enum {
    ESPNOW_NODE_UNKNOWN = 0,
    ESPNOW_NODE_S3_NCM  = 1,
    ESPNOW_NODE_C3_SLIP = 2,
} espnow_node_type_t;

#define ESPNOW_DISCOV_TYPE_BEACON   1
#define ESPNOW_DISCOV_TYPE_RESPONSE 2

typedef struct __attribute__((packed)) {
    uint32_t magic;         // ESPNOW_DISCOV_MAGIC
    uint8_t  msg_type;      // 1 = BEACON, 2 = RESPONSE
    uint8_t  sender_mac[6]; // Wi-Fi STA MAC
    uint8_t  node_type;     // espnow_node_type_t
    uint32_t ip;            // IP in network byte order (or 0)
    uint32_t uptime_s;      // uptime in seconds
} espnow_discovery_pkt_t;

typedef struct {
    uint8_t            mac[6];
    uint32_t           ip;         // IPv4 in network byte order
    espnow_node_type_t node_type;
    uint32_t           last_seen;  // FreeRTOS tick
    bool               active;
    bool               is_static;
} espnow_peer_entry_t;

// --- IPv4 Helpers ---
#define ESPNOW_IPV4_ADDR(a, b, c, d) \
    ((uint32_t)(((uint32_t)(uint8_t)(a)) | \
               (((uint32_t)(uint8_t)(b)) << 8) | \
               (((uint32_t)(uint8_t)(c)) << 16) | \
               (((uint32_t)(uint8_t)(d)) << 24)))

#define ESPNOW_IP_STR "%u.%u.%u.%u"
#define ESPNOW_IP_ARG(ip) \
    (unsigned int)(((ip) >> 0) & 0xFF), \
    (unsigned int)(((ip) >> 8) & 0xFF), \
    (unsigned int)(((ip) >> 16) & 0xFF), \
    (unsigned int)(((ip) >> 24) & 0xFF)

// --- Protocol Structures ---
typedef struct __attribute__((packed)) {
    uint16_t frame_id;
    uint8_t  frag_idx;
    uint8_t  frag_total;
    uint16_t payload_len;
} frag_hdr_t;

typedef struct __attribute__((packed)) {
    frag_hdr_t hdr;
    uint8_t    data[MAX_FRAG_PAYLOAD];
} espnow_frag_pkt_t;

typedef struct {
    uint8_t  src_mac[6];
    uint8_t  dst_mac[6];
    uint16_t len;
    uint8_t  data[MAX_PACKET_SIZE];
} pkt_item_t;

typedef struct {
    uint8_t    src_mac[6];
    uint16_t   fid;
    uint8_t    mask;
    uint8_t    active;
    uint16_t   total_len;
    uint32_t   last_tick;
    pkt_item_t pkt;
} reasm_slot_t;

// --- Shared Queues and Semaphores ---
extern QueueHandle_t espnow_tx_q;
extern SemaphoreHandle_t espnow_tx_sem;

// --- Initialization API ---

/**
 * @brief Initialize NVS flash with auto-erase if partition is corrupted or has new version.
 */
esp_err_t espnow_common_nvs_init(void);

/**
 * @brief Initialize Wi-Fi in STA mode without power saving on specified channel.
 */
esp_err_t espnow_common_wifi_init(uint8_t channel);

/**
 * @brief Initialize NVS, Wi-Fi, ESP-NOW, peer, TX queue and semaphore.
 *
 * @param peer_mac 6-byte MAC of peer (or NULL for default broadcast 0xFF:0xFF:0xFF:0xFF:0xFF:0xFF)
 * @param channel Wi-Fi channel (typically 1)
 * @param recv_cb ESP-NOW receive callback (can be NULL)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t espnow_common_init(const uint8_t *peer_mac, uint8_t channel, esp_now_recv_cb_t recv_cb);

/**
 * @brief Initialize with custom TX queue capacity.
 */
esp_err_t espnow_common_init_custom(const uint8_t *peer_mac, uint8_t channel, esp_now_recv_cb_t recv_cb, size_t tx_q_len);

// --- Peer Management ---
void espnow_set_peer_mac(const uint8_t *peer_mac);
const uint8_t *espnow_get_peer_mac(void);
const uint8_t *espnow_get_local_mac(void);
esp_err_t espnow_add_or_update_peer(const uint8_t *peer_mac, uint8_t channel);

// --- Discovery & Peer Management API ---
void espnow_set_local_ip(uint32_t ip);
uint32_t espnow_get_local_ip(void);
void espnow_set_local_node_type(espnow_node_type_t type);
esp_err_t espnow_discovery_start(espnow_node_type_t node_type, uint32_t local_ip, uint8_t channel);
esp_err_t espnow_send_discovery_beacon(void);

esp_err_t espnow_peer_table_add(const uint8_t *mac, uint32_t ip, espnow_node_type_t type, bool is_static);
esp_err_t espnow_peer_table_find_by_ip(uint32_t ip, uint8_t *out_mac);
void espnow_peer_table_update_ip(const uint8_t *mac, uint32_t ip);
size_t espnow_peer_table_count(void);
esp_err_t espnow_peer_table_get_first(uint8_t *out_mac);
void espnow_peers_age_check(void);
esp_err_t espnow_resolve_dest_mac(const uint8_t *data, size_t len, uint8_t *out_mac);
// --- Reassembly API ---

/**
 * @brief Initialize reassembly slots.
 * @param slots Slot array of size REASM_SLOTS, or NULL to use internal default slots.
 */
void espnow_reasm_init(reasm_slot_t *slots);

/**
 * @brief Process an incoming ESP-NOW fragment and reassemble into out_pkt.
 *
 * @param slots Slot array of size REASM_SLOTS, or NULL to use internal default slots.
 * @param data Pointer to raw received ESP-NOW data.
 * @param len Length of received ESP-NOW data.
 * @param header_offset Offset in pkt->data where fragment payload should be written
 *                      (0 for raw packet, 14 to reserve room for Ethernet header).
 * @param[out] out_pkt On completion, points to completed pkt_item_t with len set.
 * @return true if a complete packet was reassembled, false otherwise.
 */
bool espnow_reasm_process(reasm_slot_t *slots, const uint8_t *data, int len, size_t header_offset, pkt_item_t **out_pkt);
/**
 * @brief Process incoming fragment with peer source tracking.
 */
bool espnow_reasm_process_src(reasm_slot_t *slots, const uint8_t *src_mac, const uint8_t *data, int len, size_t header_offset, pkt_item_t **out_pkt);

/**
 * @brief Enqueue a packet to espnow_tx_q targeted to a specific peer MAC (or NULL for auto-route).
 */
esp_err_t espnow_enqueue_packet_to(const uint8_t *dst_mac, const void *data, uint16_t len, TickType_t wait_ticks);


// --- Transmission API ---

/**
 * @brief Fragment and transmit a packet over ESP-NOW.
 *
 * @param peer_mac Target MAC (or NULL to use configured peer MAC).
 * @param data Packet payload.
 * @param len Packet length (<= MAX_PACKET_SIZE).
 * @return ESP_OK on success, error code otherwise.
 */
esp_err_t espnow_send_packet(const uint8_t *peer_mac, const uint8_t *data, size_t len);

/**
 * @brief Enqueue a packet to espnow_tx_q.
 */
esp_err_t espnow_enqueue_packet(const void *data, uint16_t len, TickType_t wait_ticks);

/**
 * @brief FreeRTOS task function reading from espnow_tx_q and transmitting over ESP-NOW.
 */
void espnow_tx_task(void *arg);

/**
 * @brief Helper to create and start espnow_tx_task.
 * @param priority Task priority
 * @param core_id Core ID (tskNO_AFFINITY for single core / unpinned, or 0/1)
 */
esp_err_t espnow_start_tx_task(UBaseType_t priority, BaseType_t core_id);

/**
 * @brief Standard ESP-NOW send callback that signals espnow_tx_sem.
 */
void on_espnow_send(const wifi_tx_info_t *mac_addr, esp_now_send_status_t status);

#ifdef __cplusplus
}
#endif
