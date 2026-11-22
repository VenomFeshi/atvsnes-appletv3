#ifndef ATVSNES_BLE_PROTOCOL_H
#define ATVSNES_BLE_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define ATVSNES_BLE_SERVICE_P1 "854DEE83-73CA-4763-B413-75D42FA032F0"
#define ATVSNES_BLE_SERVICE_P2 "854DEE83-73CA-4763-B413-75D42FA032F2"
#define ATVSNES_BLE_INPUT "854DEE83-73CA-4763-B413-75D42FA032F1"
#define ATVSNES_BLE_BACK (1u << 12)
#define ATVSNES_PAD_MASK 0x0FFFu

static inline bool ATVSNESDecodeInput(const uint8_t *data, size_t size, uint16_t *buttons)
{
    if (!data || size != 3 || data[0] != 1 || (data[2] & 0xE0))
        return false;
    *buttons = (uint16_t)(data[1] | ((uint16_t)data[2] << 8));
    return true;
}

#endif
