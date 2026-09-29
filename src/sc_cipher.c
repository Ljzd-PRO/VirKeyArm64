#include "sc_cipher.h"

static uint32_t VkReadWord(const uint8_t *bytes)
{
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static void VkWriteWord(uint8_t *bytes, uint32_t value)
{
    unsigned i;
    for (i = 0; i != 4; ++i) bytes[i] = (uint8_t)(value >> (i * 8));
}

static uint32_t VkRotateLeft(uint32_t value, unsigned shift)
{
    return shift == 0 ? value : (value << shift) | (value >> (32 - shift));
}

/* Derived from the supplied x64 MulttKey image, transform at VA 0x16a70.
 * All arithmetic has explicit 32-bit unsigned wraparound. */
static uint32_t VkScHashWord(uint32_t value, uint32_t password,
                            const uint8_t secretTable[8])
{
    uint32_t digits = (password ^ UINT32_C(0x01081000)) >> 12;
    uint32_t state = 31;
    unsigned index = 0, round;
    int position;
    for (position = 10; position >= 6; --position) {
        unsigned digit = digits & 15;
        if (digit != 0 && digit < 11) state |= UINT32_C(1) << position;
        digits >>= 4;
    }
    for (round = 0; round != 39; ++round) {
        unsigned selector = (value >> (index * 8)) & 31;
        unsigned secret = (secretTable[(selector >> 2) & 0xfe] >>
                           (7 - (selector & 7))) & 1;
        uint32_t feedback = selector ^ ((secret ^ 1) & (selector >> 3)) ^
                            (selector >> 4) ^ (state >> 10) ^ (state >> 7);
        unsigned bit, low;
        if ((selector & 2) != 0) feedback ^= state >> 5;
        if ((selector & 4) != 0) feedback ^= state >> 8;
        state = ((state ^ ((selector & 1) << 2)) << 1) | (feedback & 1);
        bit = ((state >> 11) ^ secret) & 1;
        low = value & 1;
        index = low * 2 + bit;
        value = (value >> 1) ^ (low != bit ? UINT32_C(0x80500062) : 0);
    }
    return value;
}

void VkScDecodeBlock(const uint8_t input[8], uint8_t output[8],
                     uint8_t continuation[8], uint32_t password,
                     const uint8_t secretTable[8])
{
    uint32_t left = VkReadWord(input), right = VkReadWord(input + 4);
    uint32_t hash[2];
    unsigned phase;
    /* Two invertible six-round stages surround the keyed word transform.
     * The public UsbHasp block structure and independent x64 I/O captures
     * were used to establish this contract. */
    for (phase = 0; phase != 2; ++phase) {
        int shift = phase == 0 ? 25 : 10;
        int step = phase == 0 ? 5 : 2;
        uint32_t constant = phase == 0 ? UINT32_C(0x5b2c004a) :
                                         UINT32_C(0x803425c3);
        for (; shift >= 0; shift -= step) {
            uint32_t oldLeft = left;
            left = VkRotateLeft(left ^ constant, (unsigned)shift) ^ right;
            right = oldLeft;
        }
        hash[phase] = VkScHashWord(left, password, secretTable);
        {
            uint32_t oldLeft = left;
            left = hash[phase] ^ right;
            right = oldLeft;
        }
    }
    VkWriteWord(output, left);
    VkWriteWord(output + 4, right);
    if (continuation != 0) {
        VkWriteWord(continuation, hash[1]);
        VkWriteWord(continuation + 4, hash[0]);
    }
}
