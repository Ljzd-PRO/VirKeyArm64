#ifndef VIRKEY_SC_CIPHER_H
#define VIRKEY_SC_CIPHER_H

#include <stdint.h>

/* SC HASP4 decode operation. The second result contains the two intermediate
 * hash words returned by the 16-byte form of the observed IOCTL. */
void VkScDecodeBlock(const uint8_t input[8], uint8_t output[8],
                     uint8_t continuation[8], uint32_t password,
                     const uint8_t secretTable[8]);

#endif
