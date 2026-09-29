#include "sc_dump.h"

#include <string.h>

/* Windows REG_BINARY and REG_DWORD are 3 and 4 respectively. Keeping this
 * parser free of WDK headers lets the same code run in Mac host tests. */
static const uint32_t VkExpectedTypes[VK_SC_FIELD_COUNT] = {
    4, 4, 4, 4, 3, 3, 3, 3, 3
};
static const uint32_t VkExpectedLengths[VK_SC_FIELD_COUNT] = {
    4, 4, 4, 4, VK_SC_DATA_LENGTH, VK_SC_LICENSE_LENGTH,
    VK_SC_SEC_TABLE_LENGTH, VK_SC_NET_MEMORY_LENGTH, VK_SC_OPTION_LENGTH
};

static uint32_t VkReadLe32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

VkScParseResult VkParseScDump(const VkRegistryValue fields[VK_SC_FIELD_COUNT],
                             VkScDump *output)
{
    uint32_t i;
    if (fields == NULL || output == NULL) return VkScMissingField;
    for (i = 0; i < VK_SC_FIELD_COUNT; ++i) {
        if (fields[i].data == NULL) return VkScMissingField;
        if (fields[i].type != VkExpectedTypes[i]) return VkScWrongType;
        if (fields[i].length != VkExpectedLengths[i]) return VkScWrongLength;
    }
    if (VkReadLe32(fields[VkScType].data) != 1) return VkScUnsupportedType;

    memset(output, 0, sizeof(*output));
    output->serialNumber = VkReadLe32(fields[VkScSerialNumber].data);
    output->dongleType = VkReadLe32(fields[VkScDongleType].data);
    output->memory = VkReadLe32(fields[VkScMemory].data);
    memcpy(output->data, fields[VkScData].data, VK_SC_DATA_LENGTH);
    memcpy(output->license, fields[VkScLicense].data, VK_SC_LICENSE_LENGTH);
    memcpy(output->secTable, fields[VkScSecTable].data, VK_SC_SEC_TABLE_LENGTH);
    memcpy(output->netMemory, fields[VkScNetMemory].data, VK_SC_NET_MEMORY_LENGTH);
    memcpy(output->option, fields[VkScOption].data, VK_SC_OPTION_LENGTH);
    return VkScValid;
}
