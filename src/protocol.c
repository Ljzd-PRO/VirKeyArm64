#include "protocol.h"
#include "sc_cipher.h"
#include <string.h>

#define VK_IOCTL_GET_VERSION 0x9C402450u
#define VK_IOCTL_SC_TRANSACTION 0x9C402458u

VkProtocolResult VkProcessHaspVersion(const uint8_t *input,
                                      size_t inputLength,
                                      uint8_t *output, size_t outputCapacity,
                                      size_t *outputLength)
{
    static const uint8_t zeroVersion[6] = {0, 0, 0xfa, 0xfa, 0x1a, 4};
    static const uint8_t oneVersion[6] = {1, 0, 0xfa, 0xfa, 0x58, 3};
    const uint8_t *version;
    if (outputLength == NULL) return VkProtocolBadRequest;
    *outputLength = 0;
    if (input == NULL || output == NULL || inputLength != 6 || outputCapacity < 6 ||
        input[1] != 0 || input[2] != 0 || input[3] != 0)
        return VkProtocolBadRequest;
    if (input[0] == 0 && input[4] == 0 && input[5] == 0)
        version = zeroVersion;
    else if (input[0] == 1)
        version = oneVersion;
    else
        return VkProtocolBadRequest;
    memcpy(output, version, 6);
    *outputLength = 6;
    return VkProtocolOk;
}

static int VkHexNibble(uint16_t c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

static int VkNameMatches(const uint16_t *name, const uint8_t *packet)
{
    uint16_t first = 0, second = 0;
    unsigned i;
    if (name == NULL) return 0;
    for (i = 0; i < 8; ++i) {
        int nibble = VkHexNibble(name[i]);
        if (nibble < 0) return 0;
        if (i < 4) first = (uint16_t)((first << 4) | nibble);
        else second = (uint16_t)((second << 4) | nibble);
    }
    if (name[8] != 0) return 0;
    return packet[8] == (uint8_t)first &&
           packet[9] == (uint8_t)(first >> 8) &&
           packet[12] == (uint8_t)second &&
           packet[13] == (uint8_t)(second >> 8);
}

VkProtocolResult VkProcessScHaspDiscovery(const uint16_t *dumpName,
                                        uint32_t sessionToken,
                                        const uint8_t *input,
                                        size_t inputLength,
                                        uint8_t *output,
                                        size_t outputCapacity,
                                        size_t *outputLength)
{
    static const uint8_t cookie[4] = {0x89, 0xc5, 0xff, 0xff};
    if (outputLength == NULL) return VkProtocolBadRequest;
    *outputLength = 0;
    if (input == NULL || output == NULL || inputLength != 256 ||
        outputCapacity < 256 || input[0] != 3 || input[1] != 0x58 ||
        input[6] != 4 || !VkNameMatches(dumpName, input) ||
        input[24] != 0 || input[26] != 0 || input[28] != 1 ||
        input[70] != 0 || input[71] != 0 || input[72] != 0 ||
        input[73] != 0 || input[76] != 1 ||
        input[104] != 0 || input[105] != 0 ||
        input[106] != 0 || input[107] != 0)
        return VkProtocolBadRequest;

    memmove(output, input, 256);
    output[16] = 1;
    output[70] = (uint8_t)sessionToken;
    output[71] = (uint8_t)(sessionToken >> 8);
    output[72] = (uint8_t)(sessionToken >> 16);
    output[73] = (uint8_t)(sessionToken >> 24);
    memcpy(output + 104, cookie, sizeof(cookie));
    output[130] = 1;
    output[132] = 1;
    output[254] = 1;
    *outputLength = 256;
    return VkProtocolOk;
}

VkProtocolResult VkProcessGlobalDiscovery(const uint16_t *dumpName,
                                          uint32_t sessionToken,
                                          const uint8_t *input,
                                          size_t inputLength,
                                          uint8_t *output,
                                          size_t outputCapacity,
                                          size_t *outputLength)
{
    static const uint8_t cookie[4] = {0x89, 0xc5, 0xff, 0xff};
    if (outputLength == NULL) return VkProtocolBadRequest;
    *outputLength = 0;
    if (input == NULL || output == NULL || inputLength != 256 ||
        outputCapacity < 256 || input[0] != 3 || input[1] != 0x58 ||
        input[6] != 4 || !VkNameMatches(dumpName, input) ||
        input[26] != 7 || input[76] != 1 ||
        memcmp(input + 104, cookie, sizeof(cookie)) != 0)
        return VkProtocolBadRequest;
    memmove(output, input, 256);
    output[70] = (uint8_t)sessionToken;
    output[71] = (uint8_t)(sessionToken >> 8);
    output[72] = (uint8_t)(sessionToken >> 16);
    output[73] = (uint8_t)(sessionToken >> 24);
    output[76] = 0x85;
    *outputLength = 256;
    return VkProtocolOk;
}

VkProtocolResult VkProcessScIoctl(const VkScDump *dump,
                                  const uint16_t *dumpName,
                                  uint32_t code,
                                  const uint8_t *input, size_t inputLength,
                                  uint8_t *output, size_t outputCapacity,
                                  size_t *outputLength)
{
    static const uint8_t version[] = {1, 0, 0xfa, 0xfa, 0x58, 3};
    const uint8_t *packet;
    uint8_t copy[304];
    if (outputLength == NULL) return VkProtocolBadRequest;
    *outputLength = 0;
    if (dump == NULL || input == NULL || output == NULL)
        return VkProtocolBadRequest;

    if (code == VK_IOCTL_GET_VERSION) {
        if (inputLength != 6 || outputCapacity < sizeof(version) ||
            input[0] != 1 || input[1] != 0 || input[2] != 0 || input[3] != 0)
            return VkProtocolBadRequest;
        memcpy(output, version, sizeof(version));
        *outputLength = sizeof(version);
        return VkProtocolOk;
    }
    if (code != VK_IOCTL_SC_TRANSACTION) return VkProtocolUnsupportedCode;
    if (inputLength != 256 && inputLength != 264 &&
        inputLength != 272 && inputLength != 304)
        return VkProtocolBadRequest;
    if (outputCapacity < inputLength || input[0] != 3 || input[1] != 0x58 ||
        input[6] != 4 || !VkNameMatches(dumpName, input))
        return VkProtocolBadRequest;
    memcpy(copy, input, inputLength);
    packet = copy;
    if (inputLength == 264 || inputLength == 272) {
        uint32_t password = 0;
        unsigned i;
        if (packet[24] != 0x3d || packet[25] != 1 ||
            dump->option[0] != 1 || dump->dongleType != 1)
            return VkProtocolUnsupportedChallenge;
        for (i = 0; i != 8; ++i)
            password = (password << 4) | (uint32_t)VkHexNibble(dumpName[i]);
        password = (password << 16) | (password >> 16);
        VkScDecodeBlock(packet + 256, copy + 256,
                         inputLength == 272 ? copy + 264 : NULL,
                         password, dump->secTable);
        copy[16] = 1;
        copy[130] = 1;
        if (inputLength == 272) copy[132] = 0x0a;
    } else if (inputLength == 304 && packet[24] == 0x17) {
        memcpy(copy + 256, dump->data, 48);
    } else if (inputLength == 256 &&
               packet[24] == 0 && packet[132] == 0) {
        copy[16] = 1;
        copy[26] = 0;
        copy[130] = 1;
        copy[132] = 1;
        copy[254] = 1;
    } else if (inputLength == 256 && packet[24] == 0x2d) {
        copy[16] = 1;
        copy[130] = 1;
        copy[132] = 1;
    } else if (inputLength == 256 && packet[24] == 0x1d) {
        uint32_t serial = dump->serialNumber;
        copy[16] = (uint8_t)serial;
        copy[17] = (uint8_t)(serial >> 8);
        copy[130] = (uint8_t)(serial >> 16);
        copy[131] = (uint8_t)(serial >> 24);
    } else if (inputLength == 256 && packet[24] == 0x14) {
        copy[130] = 0;
        copy[131] = 0;
        copy[132] = 1;
    } else {
        return VkProtocolBadRequest;
    }
    memcpy(output, copy, inputLength);
    *outputLength = inputLength;
    return VkProtocolOk;
}
