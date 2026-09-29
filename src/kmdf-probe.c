#include <ntddk.h>
#include <wdf.h>

DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD VirKeyProbeDeviceAdd;

NTSTATUS VirKeyProbeDeviceAdd(WDFDRIVER driver, PWDFDEVICE_INIT init)
{
    WDFDEVICE device;
    UNREFERENCED_PARAMETER(driver);
    return WdfDeviceCreate(&init, WDF_NO_OBJECT_ATTRIBUTES, &device);
}

NTSTATUS DriverEntry(PDRIVER_OBJECT driver, PUNICODE_STRING registry)
{
    UNREFERENCED_PARAMETER(driver);
    UNREFERENCED_PARAMETER(registry);
    return STATUS_UNSUCCESSFUL;
}
