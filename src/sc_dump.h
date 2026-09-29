#ifndef VIRKEY_SC_DUMP_H
#define VIRKEY_SC_DUMP_H

#include <stddef.h>
#include <stdint.h>

#define VK_SC_DATA_LENGTH 112u
#define VK_SC_LICENSE_LENGTH 16u
#define VK_SC_SEC_TABLE_LENGTH 8u
#define VK_SC_NET_MEMORY_LENGTH 12u
#define VK_SC_OPTION_LENGTH 13u
#define VK_SC_FIELD_COUNT 9u

typedef enum VkScField {
    VkScType,
    VkScSerialNumber,
    VkScDongleType,
    VkScMemory,
    VkScData,
    VkScLicense,
    VkScSecTable,
    VkScNetMemory,
    VkScOption
} VkScField;

typedef struct VkRegistryValue {
    uint32_t type;
    uint32_t length;
    const uint8_t *data;
} VkRegistryValue;

typedef struct VkScDump {
    uint32_t serialNumber;
    uint32_t dongleType;
    uint32_t memory;
    uint8_t data[VK_SC_DATA_LENGTH];
    uint8_t license[VK_SC_LICENSE_LENGTH];
    uint8_t secTable[VK_SC_SEC_TABLE_LENGTH];
    uint8_t netMemory[VK_SC_NET_MEMORY_LENGTH];
    uint8_t option[VK_SC_OPTION_LENGTH];
} VkScDump;

typedef enum VkScParseResult {
    VkScValid = 0,
    VkScMissingField,
    VkScWrongType,
    VkScWrongLength,
    VkScUnsupportedType
} VkScParseResult;

VkScParseResult VkParseScDump(const VkRegistryValue fields[VK_SC_FIELD_COUNT],
                             VkScDump *output);

#endif
