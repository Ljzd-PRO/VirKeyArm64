#include "registry.h"

#define VK_LOG(level, format, ...) \
    DbgPrintEx(DPFLTR_IHVDRIVER_ID, level, "VirKeyArm64: " format, __VA_ARGS__)

typedef struct VkValueStorage {
    VkRegistryValue value;
    UCHAR bytes[VK_SC_DATA_LENGTH];
} VkValueStorage;

static const WCHAR *const VkValueNames[VK_SC_FIELD_COUNT] = {
    L"Type", L"SN", L"DongleType", L"Memory", L"Data", L"License",
    L"SecTable", L"NetMemory", L"Option"
};

static NTSTATUS VkOpenAbsolute(PCWSTR path, ACCESS_MASK access, PHANDLE key)
{
    OBJECT_ATTRIBUTES attributes;
    UNICODE_STRING name;
    RtlInitUnicodeString(&name, path);
    InitializeObjectAttributes(&attributes, &name,
                               OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE,
                               NULL, NULL);
    return ZwOpenKey(key, access, &attributes);
}

static NTSTATUS VkOpenChild(HANDLE parent, PCWSTR name, ACCESS_MASK access,
                            PHANDLE key)
{
    OBJECT_ATTRIBUTES attributes;
    UNICODE_STRING childName;
    RtlInitUnicodeString(&childName, name);
    InitializeObjectAttributes(&attributes, &childName,
                               OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE,
                               parent, NULL);
    return ZwOpenKey(key, access, &attributes);
}

static NTSTATUS VkReadValue(HANDLE key, PCWSTR name, VkValueStorage *storage)
{
    UCHAR buffer[sizeof(KEY_VALUE_PARTIAL_INFORMATION) + VK_SC_DATA_LENGTH];
    PKEY_VALUE_PARTIAL_INFORMATION info = (PKEY_VALUE_PARTIAL_INFORMATION)buffer;
    UNICODE_STRING valueName;
    ULONG length = 0;
    NTSTATUS status;

    RtlInitUnicodeString(&valueName, name);
    status = ZwQueryValueKey(key, &valueName, KeyValuePartialInformation,
                             info, sizeof(buffer), &length);
    if (!NT_SUCCESS(status)) return status;
    if (info->DataLength > sizeof(storage->bytes)) return STATUS_BUFFER_OVERFLOW;
    storage->value.type = info->Type;
    storage->value.length = info->DataLength;
    RtlCopyMemory(storage->bytes, info->Data, info->DataLength);
    storage->value.data = storage->bytes;
    return STATUS_SUCCESS;
}

static NTSTATUS VkReadOne(HANDLE key, VkScDump *dump, PCWSTR name)
{
    VkValueStorage values[VK_SC_FIELD_COUNT];
    VkRegistryValue raw[VK_SC_FIELD_COUNT];
    VkScParseResult parsed;
    ULONG i;
    NTSTATUS status;

    RtlZeroMemory(values, sizeof(values));
    status = VkReadValue(key, VkValueNames[VkScType], &values[VkScType]);
    if (!NT_SUCCESS(status)) return status;
    if (values[VkScType].value.type == REG_DWORD &&
        values[VkScType].value.length == sizeof(ULONG) &&
        *(UNALIGNED ULONG *)values[VkScType].bytes != 1) {
        VK_LOG(DPFLTR_INFO_LEVEL, "ignoring non-SC dump %ws\n", name);
        return STATUS_NOT_SUPPORTED;
    }
    for (i = 1; i < VK_SC_FIELD_COUNT; ++i) {
        status = VkReadValue(key, VkValueNames[i], &values[i]);
        if (!NT_SUCCESS(status)) return status;
    }
    for (i = 0; i < VK_SC_FIELD_COUNT; ++i) raw[i] = values[i].value;
    parsed = VkParseScDump(raw, dump);
    if (parsed != VkScValid) {
        VK_LOG(DPFLTR_ERROR_LEVEL, "invalid SC dump %ws, field result %u\n",
               name, (ULONG)parsed);
        return STATUS_INVALID_PARAMETER;
    }
    return STATUS_SUCCESS;
}

static VOID VkScanRoot(HANDLE root, HANDLE overlay, VkScDump *chosen,
                       WCHAR chosenName[VK_MAX_DUMP_NAME_CHARS], BOOLEAN *found,
                       BOOLEAN fromNewRoot, BOOLEAN *selectedFromNewRoot)
{
    UCHAR buffer[sizeof(KEY_BASIC_INFORMATION) +
                 VK_MAX_DUMP_NAME_CHARS * sizeof(WCHAR)];
    PKEY_BASIC_INFORMATION info = (PKEY_BASIC_INFORMATION)buffer;
    ULONG index, returned, chars;
    HANDLE child, shadow;
    WCHAR name[VK_MAX_DUMP_NAME_CHARS];
    VkScDump candidate;
    UNICODE_STRING candidateString, chosenString;
    NTSTATUS status;

    for (index = 0;; ++index) {
        status = ZwEnumerateKey(root, index, KeyBasicInformation,
                                info, sizeof(buffer), &returned);
        if (status == STATUS_NO_MORE_ENTRIES) break;
        if (!NT_SUCCESS(status)) {
            VK_LOG(DPFLTR_ERROR_LEVEL, "enumeration failed at %u: %08X\n",
                   index, (ULONG)status);
            break;
        }
        if ((info->NameLength % sizeof(WCHAR)) != 0) continue;
        chars = info->NameLength / sizeof(WCHAR);
        if (chars == 0 || chars >= VK_MAX_DUMP_NAME_CHARS) continue;
        RtlCopyMemory(name, info->Name, info->NameLength);
        name[chars] = L'\0';

        /* An entry in the new root shadows its old-root namesake even if
         * the new entry is malformed. This prevents accidental fallback. */
        if (overlay != NULL) {
            status = VkOpenChild(overlay, name, KEY_QUERY_VALUE, &shadow);
            if (NT_SUCCESS(status)) {
                ZwClose(shadow);
                continue;
            }
        }
        status = VkOpenChild(root, name, KEY_QUERY_VALUE, &child);
        if (!NT_SUCCESS(status)) continue;
        status = VkReadOne(child, &candidate, name);
        ZwClose(child);
        if (!NT_SUCCESS(status)) continue;

        RtlInitUnicodeString(&candidateString, name);
        RtlInitUnicodeString(&chosenString, chosenName);
        if (!*found || RtlCompareUnicodeString(&candidateString, &chosenString,
                                               TRUE) < 0) {
            *chosen = candidate;
            RtlCopyMemory(chosenName, name, (chars + 1) * sizeof(WCHAR));
            *found = TRUE;
            *selectedFromNewRoot = fromNewRoot;
        }
    }
}

NTSTATUS VkLoadScDump(VkScDump *dump,
                      WCHAR selectedName[VK_MAX_DUMP_NAME_CHARS],
                      BOOLEAN *selectedFromNewRoot)
{
    static const WCHAR oldPath[] =
        L"\\Registry\\Machine\\System\\CurrentControlSet\\MulttKey\\Dumps";
    static const WCHAR newPath[] =
        L"\\Registry\\Machine\\System\\CurrentControlSet\\VirKeyArm64\\Dumps";
    HANDLE oldRoot = NULL, newRoot = NULL;
    BOOLEAN found = FALSE;

    if (dump == NULL || selectedName == NULL || selectedFromNewRoot == NULL)
        return STATUS_INVALID_PARAMETER;
    selectedName[0] = L'\0';
    *selectedFromNewRoot = FALSE;
    VkOpenAbsolute(newPath, KEY_ENUMERATE_SUB_KEYS | KEY_QUERY_VALUE, &newRoot);
    VkOpenAbsolute(oldPath, KEY_ENUMERATE_SUB_KEYS | KEY_QUERY_VALUE, &oldRoot);
    if (newRoot != NULL)
        VkScanRoot(newRoot, NULL, dump, selectedName, &found,
                   TRUE, selectedFromNewRoot);
    if (oldRoot != NULL)
        VkScanRoot(oldRoot, newRoot, dump, selectedName, &found,
                   FALSE, selectedFromNewRoot);
    if (newRoot != NULL) ZwClose(newRoot);
    if (oldRoot != NULL) ZwClose(oldRoot);
    return found ? STATUS_SUCCESS : STATUS_NOT_FOUND;
}
