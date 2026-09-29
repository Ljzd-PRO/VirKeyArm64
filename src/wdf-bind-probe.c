#include <ntddk.h>
/* The v1 loader record is documented by Microsoft's WDF source in fxldr.h.
 * This probe isolates WdfVersionBind from the WDK's normal entry stub. */
typedef struct VkWdfBindInfo {
    ULONG size;
    WCHAR *component;
    ULONG major, minor, build;
    ULONG functionCount;
    PVOID *functionTable;
    PVOID module;
} VkWdfBindInfo;

static PVOID VkWdfFunctions[458];
static WCHAR VkWdfComponent[] = L"KmdfLibrary";
static VkWdfBindInfo VkBindInfo = {
    sizeof(VkWdfBindInfo), VkWdfComponent, 1, 33, 0,
    RTL_NUMBER_OF(VkWdfFunctions), VkWdfFunctions, NULL
};
extern NTSTATUS WdfVersionBind(PDRIVER_OBJECT, PUNICODE_STRING, PVOID, PVOID *);
extern NTSTATUS WdfVersionUnbind(PUNICODE_STRING, PVOID, PVOID);

static VOID SaveStatus(PUNICODE_STRING path, PCWSTR valueName, ULONG value)
{
    OBJECT_ATTRIBUTES attributes;
    UNICODE_STRING name;
    HANDLE key;
    InitializeObjectAttributes(&attributes, path,
                               OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE,
                               NULL, NULL);
    if (NT_SUCCESS(ZwOpenKey(&key, KEY_SET_VALUE, &attributes))) {
        RtlInitUnicodeString(&name, valueName);
        ZwSetValueKey(key, &name, 0, REG_DWORD, &value, sizeof(value));
        ZwClose(key);
    }
}

NTSTATUS DriverEntry(PDRIVER_OBJECT driver, PUNICODE_STRING registry)
{
    PVOID globals = NULL;
    NTSTATUS status;
    SaveStatus(registry, L"BindProbeEntered", 1);
    status = WdfVersionBind(driver, registry, &VkBindInfo, &globals);
    SaveStatus(registry, L"BindProbeStatus", (ULONG)status);
    if (NT_SUCCESS(status)) WdfVersionUnbind(registry, &VkBindInfo, globals);
    return STATUS_UNSUCCESSFUL;
}
