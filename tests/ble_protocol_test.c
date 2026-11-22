#include <assert.h>
#include <stdio.h>
#include "ble_protocol.h"

int main(void)
{
    uint16_t buttons = 0;
    const uint8_t diagonalAndAction[] = {1, (1u << 4) | (1u << 7), 1u};
    const uint8_t back[] = {1, 0, 0x10};
    const uint8_t release[] = {1, 0, 0};
    const uint8_t invalidBit[] = {1, 0, 0x20};
    const uint8_t wrongVersion[] = {2, 0, 0};
    assert(ATVSNESDecodeInput(diagonalAndAction, sizeof(diagonalAndAction), &buttons));
    assert(buttons == ((1u << 4) | (1u << 7) | (1u << 8)));
    assert(ATVSNESDecodeInput(back, sizeof(back), &buttons));
    assert(buttons == ATVSNES_BLE_BACK);
    assert((buttons & ATVSNES_PAD_MASK) == 0);
    assert(ATVSNESDecodeInput(release, sizeof(release), &buttons) && buttons == 0);
    assert(!ATVSNESDecodeInput(invalidBit, sizeof(invalidBit), &buttons));
    assert(!ATVSNESDecodeInput(wrongVersion, sizeof(wrongVersion), &buttons));
    assert(!ATVSNESDecodeInput(release, sizeof(release) - 1, &buttons));
    puts("Bluetooth input packets: held buttons, release, and invalid packets passed.");
    return 0;
}
