#include <ntddk.h>

DRIVER_INITIALIZE DriverEntry;
PVOID volatile VirKeyRelocationProbe = (PVOID)&DriverEntry;

NTSTATUS DriverEntry(PDRIVER_OBJECT driver, PUNICODE_STRING registry)
{
    UNREFERENCED_PARAMETER(driver);
    UNREFERENCED_PARAMETER(registry);
    if (VirKeyRelocationProbe == NULL) return STATUS_INVALID_PARAMETER;
    return STATUS_UNSUCCESSFUL;
}
