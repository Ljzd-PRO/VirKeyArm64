#ifndef VIRKEY_PROTOCOL_H
#define VIRKEY_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>
#include "sc_dump.h"

typedef enum VkProtocolResult {
    VkProtocolOk = 0,
    VkProtocolBadRequest,
    VkProtocolUnsupportedChallenge,
    VkProtocolUnsupportedCode
} VkProtocolResult;

/* Pure request/response core. The buffers may alias for METHOD_BUFFERED. */
VkProtocolResult VkProcessScIoctl(const VkScDump *dump,
                                  const uint16_t *dumpName,
                                  uint32_t code,
                                  const uint8_t *input, size_t inputLength,
                                  uint8_t *output, size_t outputCapacity,
                                  size_t *outputLength);

VkProtocolResult VkProcessHaspVersion(const uint8_t *input,
                                      size_t inputLength,
                                      uint8_t *output, size_t outputCapacity,
                                      size_t *outputLength);

VkProtocolResult VkProcessScHaspDiscovery(const uint16_t *dumpName,
                                        uint32_t sessionToken,
                                        const uint8_t *input,
                                        size_t inputLength,
                                        uint8_t *output,
                                        size_t outputCapacity,
                                        size_t *outputLength);

VkProtocolResult VkProcessGlobalDiscovery(const uint16_t *dumpName,
                                          uint32_t sessionToken,
                                          const uint8_t *input,
                                          size_t inputLength,
                                          uint8_t *output,
                                          size_t outputCapacity,
                                          size_t *outputLength);

#endif
