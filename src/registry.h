#ifndef VIRKEY_REGISTRY_H
#define VIRKEY_REGISTRY_H

#include <ntddk.h>
#include "sc_dump.h"

#define VK_MAX_DUMP_NAME_CHARS 128u

NTSTATUS VkLoadScDump(VkScDump *dump,
                      WCHAR selectedName[VK_MAX_DUMP_NAME_CHARS],
                      BOOLEAN *selectedFromNewRoot);

#endif
