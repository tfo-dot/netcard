idf_component_register(
    SRCS "espnow_common.c"
    INCLUDE_DIRS "include" "."
    REQUIRES esp_wifi nvs_flash esp_netif esp_event esp_timer
)
