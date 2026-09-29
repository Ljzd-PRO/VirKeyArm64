/*
 * VirKeyArm64 SC registry, USB enumeration, and observed startup protocol.
 * Includes the verified SC block decode; other commands remain unsupported.
 */
#include <ntddk.h>
#include <wdf.h>
#include <usb.h>
#include <wdfusb.h>
#include <usbioctl.h>
#include <UdeCx.h>
#include "registry.h"
#include "protocol.h"

#define VIRKEY_POOL_TAG 'kriV'

typedef struct _VIRKEY_DEVICE_CONTEXT {
    UDECXUSBDEVICE UsbDevice;
    UDECXUSBENDPOINT ControlEndpoint;
    WDFQUEUE ControlQueue;
    WDFDEVICE GlobalControlDevice;
    BOOLEAN GlobalPdLinkCreated;
    VkScDump ScDump;
    WCHAR DumpName[VK_MAX_DUMP_NAME_CHARS];
    BOOLEAN SelectedFromNewRoot;
} VIRKEY_DEVICE_CONTEXT, *PVIRKEY_DEVICE_CONTEXT;

typedef struct _VIRKEY_FUNCTION_CONTEXT {
    ULONG observedCount;
    ULONG observedCodes[32];
    ULONG unsupportedChallenges;
    ULONG discoveryToken;
    BOOLEAN IsHasp;
    VkScDump ScDump;
    WCHAR DumpName[VK_MAX_DUMP_NAME_CHARS];
} VIRKEY_FUNCTION_CONTEXT, *PVIRKEY_FUNCTION_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(VIRKEY_DEVICE_CONTEXT, VirKeyGetContext)
WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(VIRKEY_FUNCTION_CONTEXT, VirKeyGetFunctionContext)

DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD VirKeyEvtDeviceAdd;
EVT_WDF_IO_QUEUE_IO_INTERNAL_DEVICE_CONTROL VirKeyEvtControl;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL VirKeyEvtFunctionControl;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL VirKeyEvtGlobalControl;
EVT_WDF_OBJECT_CONTEXT_CLEANUP VirKeyRootCleanup;
EVT_UDECX_WDF_DEVICE_QUERY_USB_CAPABILITY VirKeyEvtQueryCapability;
EVT_UDECX_USB_ENDPOINT_RESET VirKeyEvtEndpointReset;

/* The revision is observed on the working x64 MulttKey device. Remaining
 * descriptor fields are provisional until reference capture is complete. */
static const UCHAR VirKeyDeviceDescriptor[] = {
    18, 1, 0x00, 0x01, 0xff, 0, 0, 8,
    0x29, 0x05, 0x01, 0x00, 0x21, 0x03, 0, 0, 0, 1
};

static const UCHAR VirKeyConfigurationDescriptor[] = {
    9, 2, 18, 0, 1, 1, 0, 0x80, 27,
    9, 4, 0, 0, 0, 0xff, 0, 0, 0
};

/* Two device interfaces observed on the working x64 aksusb stack. */
static const GUID VirKeySentinelInterfaceA =
    {0x29db6d11, 0xbc3c, 0x11d7, {0xb4,0x7f,0x00,0xc0,0xdf,0xee,0x4d,0x8c}};
static const GUID VirKeySentinelInterfaceB =
    {0xbce9d0f1, 0xf7db, 0x11d7, {0xb4,0xbb,0x00,0xc0,0xdf,0xee,0x4d,0x8c}};
static const GUID VirKeyHaspInterface =
    {0x7ab02247, 0x3798, 0x44cd, {0x84,0x72,0x24,0x35,0x64,0x97,0x5f,0x04}};

static const UCHAR VirKeyGlobalDevices[] = {
    1,0,0,0, 0,0,0,0, 0x78,0x03,0,0, 0,0,0,0,
    2,0,1,0, 0,0,0,0, 0xf8,0x03,0,0, 0,0,0,0,
    0,0,0,0, 0,0,0,0
};
static ULONG VirKeyGlobalDiscoveryToken;
static WCHAR VirKeyGlobalDumpName[VK_MAX_DUMP_NAME_CHARS];

static VOID VirKeyRecordStatus(PUNICODE_STRING path, PCWSTR valueName, ULONG value)
{
    OBJECT_ATTRIBUTES attributes;
    UNICODE_STRING name;
    HANDLE key;
    InitializeObjectAttributes(&attributes, path,
                               OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    if (NT_SUCCESS(ZwOpenKey(&key, KEY_SET_VALUE, &attributes))) {
        RtlInitUnicodeString(&name, valueName);
        ZwSetValueKey(key, &name, 0, REG_DWORD, &value, sizeof(value));
        ZwClose(key);
    }
}

static VOID VirKeyRecordBytes(PUNICODE_STRING path, PCWSTR valueName,
                             const VOID *bytes, ULONG length)
{
    OBJECT_ATTRIBUTES attributes;
    UNICODE_STRING name;
    HANDLE key;
    InitializeObjectAttributes(&attributes, path,
                               OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    if (NT_SUCCESS(ZwOpenKey(&key, KEY_SET_VALUE, &attributes))) {
        RtlInitUnicodeString(&name, valueName);
        ZwSetValueKey(key, &name, 0, REG_BINARY, (PVOID)bytes, length);
        ZwClose(key);
    }
}

static VOID VirKeyRecordObserved(BOOLEAN isHasp, ULONG index, ULONG code,
                                ULONG inputLength, ULONG outputLength,
                                WDFREQUEST request)
{
    UNICODE_STRING path;
    WCHAR codeName[] = L"ObservedIoctl00";
    WCHAR inputName[] = L"ObservedInput00";
    WCHAR outputName[] = L"ObservedOutput00";
    WCHAR payloadName[] = L"ObservedPayload00";
    static const WCHAR hex[] = L"0123456789ABCDEF";
    PVOID inputBuffer;
    size_t actualLength;
    RtlInitUnicodeString(&path, isHasp ?
        L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\akshasp" :
        L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\aksusb");
    codeName[13] = inputName[13] = outputName[14] = hex[(index >> 4) & 15];
    codeName[14] = inputName[14] = outputName[15] = hex[index & 15];
    payloadName[15] = hex[(index >> 4) & 15];
    payloadName[16] = hex[index & 15];
    VirKeyRecordStatus(&path, codeName, code);
    VirKeyRecordStatus(&path, inputName, inputLength);
    VirKeyRecordStatus(&path, outputName, outputLength);
    if (NT_SUCCESS(WdfRequestRetrieveInputBuffer(request, 1, &inputBuffer,
                                                 &actualLength))) {
        VirKeyRecordBytes(&path, payloadName, inputBuffer,
                          (ULONG)(actualLength < 64 ? actualLength : 64));
    }
}

VOID VirKeyEvtFunctionControl(WDFQUEUE Queue, WDFREQUEST Request,
                              size_t OutputBufferLength, size_t InputBufferLength,
                              ULONG IoControlCode)
{
    PVIRKEY_FUNCTION_CONTEXT context =
        VirKeyGetFunctionContext(WdfIoQueueGetDevice(Queue));
    PVOID outputBuffer;
    size_t actualLength;
    ULONG response;
    VkProtocolResult protocolResult;
    PVOID inputBuffer;
    size_t inputActualLength;
    size_t written = 0;
    NTSTATUS status;
    ULONG i;
    for (i = 0; i < context->observedCount; ++i)
        if (context->observedCodes[i] == IoControlCode) break;
    if (i == context->observedCount && i < RTL_NUMBER_OF(context->observedCodes)) {
        context->observedCodes[i] = IoControlCode;
        context->observedCount = i + 1;
        VirKeyRecordObserved(context->IsHasp, i, IoControlCode,
                             (ULONG)InputBufferLength, (ULONG)OutputBufferLength,
                             Request);
    }
    if (IoControlCode == 0x9C412600 || IoControlCode == 0x9C412640) {
        response = IoControlCode == 0x9C412600 ? 0x32C : 0x120;
        status = WdfRequestRetrieveOutputBuffer(Request, sizeof(response),
                                                &outputBuffer, &actualLength);
        if (NT_SUCCESS(status)) {
            RtlCopyMemory(outputBuffer, &response, sizeof(response));
            WdfRequestCompleteWithInformation(Request, STATUS_SUCCESS,
                                              sizeof(response));
        } else {
            WdfRequestComplete(Request, status);
        }
        return;
    }
    if (IoControlCode == 0x9C402450 || IoControlCode == 0x9C402458) {
        status = WdfRequestRetrieveInputBuffer(Request, InputBufferLength,
                                               &inputBuffer, &inputActualLength);
        if (!NT_SUCCESS(status)) {
            WdfRequestComplete(Request, status);
            return;
        }
        status = WdfRequestRetrieveOutputBuffer(Request, OutputBufferLength,
                                                &outputBuffer, &actualLength);
        if (!NT_SUCCESS(status)) {
            WdfRequestComplete(Request, status);
            return;
        }
        if (context->IsHasp && IoControlCode == 0x9C402450) {
            protocolResult = VkProcessHaspVersion(
                (const uint8_t *)inputBuffer, InputBufferLength,
                (uint8_t *)outputBuffer, OutputBufferLength, &written);
        } else {
            protocolResult = VkProtocolBadRequest;
            if (context->IsHasp && IoControlCode == 0x9C402458 &&
                InputBufferLength == 256)
                protocolResult = VkProcessScHaspDiscovery(
                    (const uint16_t *)context->DumpName,
                    context->discoveryToken,
                    (const uint8_t *)inputBuffer, InputBufferLength,
                    (uint8_t *)outputBuffer, OutputBufferLength, &written);
            if (protocolResult != VkProtocolOk)
                protocolResult = VkProcessScIoctl(
                    &context->ScDump, (const uint16_t *)context->DumpName,
                    IoControlCode, (const uint8_t *)inputBuffer,
                    InputBufferLength, (uint8_t *)outputBuffer,
                    OutputBufferLength, &written);
        }
        if (protocolResult == VkProtocolOk) {
            WdfRequestCompleteWithInformation(Request, STATUS_SUCCESS, written);
        } else if (protocolResult == VkProtocolUnsupportedChallenge) {
            UNICODE_STRING path;
            ++context->unsupportedChallenges;
            RtlInitUnicodeString(&path, context->IsHasp ?
                L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\akshasp" :
                L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\aksusb");
            VirKeyRecordStatus(&path, L"UnsupportedChallengeCount",
                               context->unsupportedChallenges);
            VirKeyRecordStatus(&path, L"LastChallengeLength",
                               (ULONG)InputBufferLength);
            VirKeyRecordBytes(&path, L"LastChallengeTail",
                              (const UCHAR *)inputBuffer + InputBufferLength - 16,
                              16);
            WdfRequestComplete(Request, STATUS_NOT_SUPPORTED);
        } else {
            WdfRequestComplete(Request, STATUS_INVALID_DEVICE_REQUEST);
        }
        return;
    }
    WdfRequestComplete(Request, STATUS_NOT_SUPPORTED);
}

static NTSTATUS VirKeyCreateHaspPdo(WDFDEVICE parent)
{
    PWDFDEVICE_INIT init = WdfPdoInitAllocate(parent);
    WDFDEVICE child = NULL;
    UNICODE_STRING hardwareId, instanceId, description, location;
    NTSTATUS status;
    if (init == NULL) return STATUS_INSUFFICIENT_RESOURCES;
    RtlInitUnicodeString(&hardwareId, L"USB\\Hasp");
    RtlInitUnicodeString(&instanceId, L"SC00");
    RtlInitUnicodeString(&description, L"SafeNet Inc. Key");
    RtlInitUnicodeString(&location, L"VirKeyArm64 virtual USB key");
    WdfDeviceInitSetDeviceType(init, FILE_DEVICE_BUS_EXTENDER);
    status = WdfPdoInitAssignDeviceID(init, &hardwareId);
    if (!NT_SUCCESS(status)) goto Exit;
    status = WdfPdoInitAddHardwareID(init, &hardwareId);
    if (!NT_SUCCESS(status)) goto Exit;
    status = WdfPdoInitAddCompatibleID(init, &hardwareId);
    if (!NT_SUCCESS(status)) goto Exit;
    status = WdfPdoInitAssignInstanceID(init, &instanceId);
    if (!NT_SUCCESS(status)) goto Exit;
    status = WdfPdoInitAddDeviceText(init, &description, &location, 0x409);
    if (!NT_SUCCESS(status)) goto Exit;
    WdfPdoInitSetDefaultLocale(init, 0x409);
    status = WdfDeviceCreate(&init, WDF_NO_OBJECT_ATTRIBUTES, &child);
    if (!NT_SUCCESS(status)) goto Exit;
    status = WdfFdoAddStaticChild(parent, child);
Exit:
    if (!NT_SUCCESS(status)) {
        if (init != NULL) WdfDeviceInitFree(init);
        if (child != NULL) WdfObjectDelete(child);
    }
    return status;
}

static NTSTATUS VirKeyFunctionDeviceAdd(PWDFDEVICE_INIT DeviceInit, BOOLEAN isHasp)
{
    WDFDEVICE device;
    WDF_OBJECT_ATTRIBUTES attributes, queueAttributes;
    WDF_IO_QUEUE_CONFIG queueConfig;
    WDFQUEUE queue;
    NTSTATUS status;
    BOOLEAN selectedFromNewRoot;
    LARGE_INTEGER discoveryTime;

    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attributes, VIRKEY_FUNCTION_CONTEXT);
    status = WdfDeviceCreate(&DeviceInit, &attributes, &device);
    if (!NT_SUCCESS(status)) return status;
    RtlZeroMemory(VirKeyGetFunctionContext(device), sizeof(VIRKEY_FUNCTION_CONTEXT));
    VirKeyGetFunctionContext(device)->IsHasp = isHasp;
    KeQuerySystemTimePrecise(&discoveryTime);
    VirKeyGetFunctionContext(device)->discoveryToken =
        ((ULONG)(discoveryTime.QuadPart >> 8) & 0xFFFF0000u) | 0x7488u;
    status = VkLoadScDump(&VirKeyGetFunctionContext(device)->ScDump,
                          VirKeyGetFunctionContext(device)->DumpName,
                          &selectedFromNewRoot);
    if (!NT_SUCCESS(status)) return status;
    status = WdfDeviceCreateDeviceInterface(device, isHasp ?
        &VirKeyHaspInterface : &VirKeySentinelInterfaceA, NULL);
    if (!NT_SUCCESS(status)) return status;
    if (!isHasp) {
        status = WdfDeviceCreateDeviceInterface(device, &VirKeySentinelInterfaceB, NULL);
        if (!NT_SUCCESS(status)) return status;
    }

    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queueConfig, WdfIoQueueDispatchSequential);
    queueConfig.EvtIoDeviceControl = VirKeyEvtFunctionControl;
    WDF_OBJECT_ATTRIBUTES_INIT(&queueAttributes);
    queueAttributes.ExecutionLevel = WdfExecutionLevelPassive;
    status = WdfIoQueueCreate(device, &queueConfig, &queueAttributes, &queue);
    if (!NT_SUCCESS(status)) return status;
    return isHasp ? STATUS_SUCCESS : VirKeyCreateHaspPdo(device);
}

VOID VirKeyEvtGlobalControl(WDFQUEUE Queue, WDFREQUEST Request,
                            size_t OutputBufferLength, size_t InputBufferLength,
                            ULONG IoControlCode)
{
    static const UCHAR version[] = {0,0,0xfa,0xfa,0x5d,3};
    ULONG globalVersion = 0x32c;
    const VOID *response = NULL;
    size_t responseLength = 0;
    PVOID outputBuffer;
    size_t actualLength;
    PVOID inputBuffer;
    size_t inputActualLength;
    size_t written;
    VkProtocolResult protocolResult;
    NTSTATUS status;
    UNREFERENCED_PARAMETER(Queue);
    if (IoControlCode == 0x9C402458 && InputBufferLength == 256 &&
        OutputBufferLength >= 256) {
        status = WdfRequestRetrieveInputBuffer(Request, 256,
                                               &inputBuffer, &inputActualLength);
        if (!NT_SUCCESS(status)) {
            WdfRequestComplete(Request, status);
            return;
        }
        status = WdfRequestRetrieveOutputBuffer(Request, 256,
                                                &outputBuffer, &actualLength);
        if (!NT_SUCCESS(status)) {
            WdfRequestComplete(Request, status);
            return;
        }
        protocolResult = VkProcessGlobalDiscovery(
            (const uint16_t *)VirKeyGlobalDumpName,
            VirKeyGlobalDiscoveryToken, (const uint8_t *)inputBuffer,
            InputBufferLength, (uint8_t *)outputBuffer, OutputBufferLength,
            &written);
        if (protocolResult == VkProtocolOk)
            WdfRequestCompleteWithInformation(Request, STATUS_SUCCESS, written);
        else
            WdfRequestComplete(Request, STATUS_INVALID_DEVICE_REQUEST);
        return;
    }
    if (IoControlCode == 0x9C412600 && InputBufferLength == 16) {
        response = &globalVersion;
        responseLength = sizeof(globalVersion);
    } else if (IoControlCode == 0x9C402450 && InputBufferLength == 6) {
        response = version;
        responseLength = sizeof(version);
    } else if (IoControlCode == 0x9C4024A8 && InputBufferLength == 8192) {
        response = VirKeyGlobalDevices;
        responseLength = sizeof(VirKeyGlobalDevices);
    } else {
        WdfRequestComplete(Request, STATUS_NOT_SUPPORTED);
        return;
    }
    if (OutputBufferLength < responseLength) {
        WdfRequestComplete(Request, STATUS_BUFFER_TOO_SMALL);
        return;
    }
    status = WdfRequestRetrieveOutputBuffer(Request, responseLength,
                                            &outputBuffer, &actualLength);
    if (!NT_SUCCESS(status)) {
        WdfRequestComplete(Request, status);
        return;
    }
    RtlCopyMemory(outputBuffer, response, responseLength);
    WdfRequestCompleteWithInformation(Request, STATUS_SUCCESS, responseLength);
}

static NTSTATUS VirKeyCreateGlobalControl(WDFDEVICE root, WDFDEVICE *created,
                                         BOOLEAN *pdLinkCreated)
{
    UNICODE_STRING security, deviceName, legacyName, pdName;
    UNICODE_STRING servicePath;
    PWDFDEVICE_INIT init;
    WDFDEVICE control = NULL;
    WDFQUEUE queue;
    WDF_IO_QUEUE_CONFIG queueConfig;
    NTSTATUS status;
    ULONG stage = 1;
    RtlInitUnicodeString(&servicePath,
        L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\aksusb");
    RtlInitUnicodeString(&security, L"D:P(A;;GA;;;SY)(A;;GA;;;BA)");
    RtlInitUnicodeString(&deviceName, L"\\Device\\VirKeyArm64Control");
    RtlInitUnicodeString(&legacyName, L"\\DosDevices\\FEnteDev");
    RtlInitUnicodeString(&pdName, L"\\DosDevices\\USBPDCOM");
    init = WdfControlDeviceInitAllocate(WdfDeviceGetDriver(root), &security);
    if (init == NULL) {
        VirKeyRecordStatus(&servicePath, L"GlobalStage", stage);
        VirKeyRecordStatus(&servicePath, L"GlobalStatus", STATUS_INSUFFICIENT_RESOURCES);
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    WdfDeviceInitSetDeviceType(init, FILE_DEVICE_UNKNOWN);
    stage = 2;
    status = WdfDeviceInitAssignName(init, &deviceName);
    if (!NT_SUCCESS(status)) goto Exit;
    stage = 3;
    status = WdfDeviceCreate(&init, WDF_NO_OBJECT_ATTRIBUTES, &control);
    if (!NT_SUCCESS(status)) goto Exit;
    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queueConfig, WdfIoQueueDispatchSequential);
    queueConfig.EvtIoDeviceControl = VirKeyEvtGlobalControl;
    stage = 4;
    status = WdfIoQueueCreate(control, &queueConfig, WDF_NO_OBJECT_ATTRIBUTES,
                              &queue);
    if (!NT_SUCCESS(status)) goto Exit;
    stage = 5;
    status = WdfDeviceCreateSymbolicLink(control, &legacyName);
    if (!NT_SUCCESS(status)) goto Exit;
    stage = 6;
    /* KMDF permits one framework-managed DOS link for this control device.
     * The second observed legacy name is an alias to the same device. */
    status = IoCreateSymbolicLink(&pdName, &deviceName);
    if (!NT_SUCCESS(status)) goto Exit;
    *pdLinkCreated = TRUE;
    WdfControlFinishInitializing(control);
    VirKeyRecordStatus(&servicePath, L"GlobalStage", 7);
    VirKeyRecordStatus(&servicePath, L"GlobalStatus", STATUS_SUCCESS);
    *created = control;
    return STATUS_SUCCESS;
Exit:
    VirKeyRecordStatus(&servicePath, L"GlobalStage", stage);
    VirKeyRecordStatus(&servicePath, L"GlobalStatus", (ULONG)status);
    if (init != NULL) WdfDeviceInitFree(init);
    if (control != NULL) WdfObjectDelete(control);
    return status;
}

VOID VirKeyRootCleanup(WDFOBJECT Object)
{
    PVIRKEY_DEVICE_CONTEXT context = VirKeyGetContext((WDFDEVICE)Object);
    if (context->GlobalControlDevice != NULL) {
        if (context->GlobalPdLinkCreated) {
            UNICODE_STRING pdName;
            RtlInitUnicodeString(&pdName, L"\\DosDevices\\USBPDCOM");
            IoDeleteSymbolicLink(&pdName);
            context->GlobalPdLinkCreated = FALSE;
        }
        WdfObjectDelete(context->GlobalControlDevice);
        context->GlobalControlDevice = NULL;
    }
}

NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath)
{
    WDF_DRIVER_CONFIG config;
    LARGE_INTEGER discoveryTime;
    NTSTATUS status;
    KeQuerySystemTimePrecise(&discoveryTime);
    VirKeyGlobalDiscoveryToken =
        ((ULONG)(discoveryTime.QuadPart >> 8) & 0xFFFFFF00u) | 0xE8u;
    VirKeyRecordStatus(RegistryPath, L"DiagnosticStage", 1);
    WDF_DRIVER_CONFIG_INIT(&config, VirKeyEvtDeviceAdd);
    config.DriverPoolTag = VIRKEY_POOL_TAG;
    status = WdfDriverCreate(DriverObject, RegistryPath, WDF_NO_OBJECT_ATTRIBUTES,
                             &config, WDF_NO_HANDLE);
    VirKeyRecordStatus(RegistryPath, L"DiagnosticStatus", (ULONG)status);
    return status;
}

NTSTATUS VirKeyEvtQueryCapability(WDFDEVICE Device, PGUID CapabilityType,
                                  ULONG OutputBufferLength, PVOID OutputBuffer,
                                  PULONG ResultLength)
{
    UNREFERENCED_PARAMETER(Device);
    UNREFERENCED_PARAMETER(CapabilityType);
    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(OutputBuffer);
    *ResultLength = 0;
    return STATUS_NOT_SUPPORTED;
}

VOID VirKeyEvtEndpointReset(UDECXUSBENDPOINT Endpoint, WDFREQUEST Request)
{
    UNREFERENCED_PARAMETER(Endpoint);
    UdecxUrbCompleteWithNtStatus(Request, STATUS_SUCCESS);
}

VOID VirKeyEvtControl(WDFQUEUE Queue, WDFREQUEST Request,
                      size_t OutputBufferLength, size_t InputBufferLength,
                      ULONG IoControlCode)
{
    UNREFERENCED_PARAMETER(Queue);
    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(InputBufferLength);
    if (IoControlCode == IOCTL_INTERNAL_USB_SUBMIT_URB) {
        UdecxUrbCompleteWithNtStatus(Request, STATUS_NOT_SUPPORTED);
    } else {
        WdfRequestComplete(Request, STATUS_INVALID_DEVICE_REQUEST);
    }
}

NTSTATUS VirKeyEvtDeviceAdd(WDFDRIVER Driver, PWDFDEVICE_INIT DeviceInit)
{
    WCHAR hardwareIds[128];
    ULONG hardwareIdsLength = 0;
    WDFDEVICE device;
    WDF_OBJECT_ATTRIBUTES attributes;
    WDF_IO_QUEUE_CONFIG queueConfig;
    UDECX_WDF_DEVICE_CONFIG udeConfig;
    UDECX_USB_ENDPOINT_CALLBACKS endpointCallbacks;
    UDECX_USB_DEVICE_PLUG_IN_OPTIONS plugOptions;
    PUDECXUSBDEVICE_INIT usbInit = NULL;
    PUDECXUSBENDPOINT_INIT endpointInit = NULL;
    PVIRKEY_DEVICE_CONTEXT context;
    NTSTATUS status;

    UNREFERENCED_PARAMETER(Driver);
    status = WdfFdoInitQueryProperty(DeviceInit, DevicePropertyHardwareID,
                                     sizeof(hardwareIds), hardwareIds,
                                     &hardwareIdsLength);
    if (!NT_SUCCESS(status)) return status;
    if (hardwareIdsLength >= sizeof(L"USB\\Hasp") &&
        RtlCompareMemory(hardwareIds, L"USB\\Hasp",
                         sizeof(L"USB\\Hasp") - sizeof(WCHAR)) ==
        sizeof(L"USB\\Hasp") - sizeof(WCHAR))
        return VirKeyFunctionDeviceAdd(DeviceInit, TRUE);
    if (hardwareIdsLength >= sizeof(L"USB\\VID_0529&PID_0001") &&
        RtlCompareMemory(hardwareIds, L"USB\\VID_0529&PID_0001",
                         sizeof(L"USB\\VID_0529&PID_0001") - sizeof(WCHAR)) ==
        sizeof(L"USB\\VID_0529&PID_0001") - sizeof(WCHAR))
        return VirKeyFunctionDeviceAdd(DeviceInit, FALSE);

    status = UdecxInitializeWdfDeviceInit(DeviceInit);
    if (!NT_SUCCESS(status)) return status;

    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attributes, VIRKEY_DEVICE_CONTEXT);
    attributes.EvtCleanupCallback = VirKeyRootCleanup;
    status = WdfDeviceCreate(&DeviceInit, &attributes, &device);
    if (!NT_SUCCESS(status)) return status;
    context = VirKeyGetContext(device);
    RtlZeroMemory(context, sizeof(*context));
    status = VkLoadScDump(&context->ScDump, context->DumpName,
                          &context->SelectedFromNewRoot);
    if (!NT_SUCCESS(status)) return status;
    {
        UNICODE_STRING servicePath;
        UNICODE_STRING dumpName;
        RtlInitUnicodeString(&servicePath,
            L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\aksusb");
        RtlInitUnicodeString(&dumpName, context->DumpName);
        VirKeyRecordStatus(&servicePath, L"SelectedSerialNumber",
                            context->ScDump.serialNumber);
        VirKeyRecordStatus(&servicePath, L"SelectedFromNewRoot",
                            context->SelectedFromNewRoot ? 1 : 0);
        VirKeyRecordBytes(&servicePath, L"SelectedDumpName",
                           context->DumpName,
                           (ULONG)(dumpName.Length + sizeof(WCHAR)));
        RtlCopyMemory(VirKeyGlobalDumpName, context->DumpName,
                      dumpName.Length + sizeof(WCHAR));
    }

    UDECX_WDF_DEVICE_CONFIG_INIT(&udeConfig, VirKeyEvtQueryCapability);
    status = UdecxWdfDeviceAddUsbDeviceEmulation(device, &udeConfig);
    if (!NT_SUCCESS(status)) return status;

    WDF_IO_QUEUE_CONFIG_INIT(&queueConfig, WdfIoQueueDispatchSequential);
    queueConfig.EvtIoInternalDeviceControl = VirKeyEvtControl;
    status = WdfIoQueueCreate(device, &queueConfig, WDF_NO_OBJECT_ATTRIBUTES,
                              &context->ControlQueue);
    if (!NT_SUCCESS(status)) return status;

    usbInit = UdecxUsbDeviceInitAllocate(device);
    if (usbInit == NULL) return STATUS_INSUFFICIENT_RESOURCES;
    UdecxUsbDeviceInitSetSpeed(usbInit, UdecxUsbFullSpeed);
    UdecxUsbDeviceInitSetEndpointsType(usbInit, UdecxEndpointTypeSimple);
    status = UdecxUsbDeviceInitAddDescriptor(usbInit, (PUCHAR)VirKeyDeviceDescriptor,
                                             sizeof(VirKeyDeviceDescriptor));
    if (!NT_SUCCESS(status)) goto Exit;
    status = UdecxUsbDeviceInitAddDescriptor(usbInit,
                                             (PUCHAR)VirKeyConfigurationDescriptor,
                                             sizeof(VirKeyConfigurationDescriptor));
    if (!NT_SUCCESS(status)) goto Exit;
    status = UdecxUsbDeviceCreate(&usbInit, WDF_NO_OBJECT_ATTRIBUTES,
                                  &context->UsbDevice);
    if (!NT_SUCCESS(status)) goto Exit;

    endpointInit = UdecxUsbSimpleEndpointInitAllocate(context->UsbDevice);
    if (endpointInit == NULL) {
        status = STATUS_INSUFFICIENT_RESOURCES;
        goto Exit;
    }
    UdecxUsbEndpointInitSetEndpointAddress(endpointInit, 0);
    UDECX_USB_ENDPOINT_CALLBACKS_INIT(&endpointCallbacks, VirKeyEvtEndpointReset);
    UdecxUsbEndpointInitSetCallbacks(endpointInit, &endpointCallbacks);
    status = UdecxUsbEndpointCreate(&endpointInit, WDF_NO_OBJECT_ATTRIBUTES,
                                     &context->ControlEndpoint);
    if (!NT_SUCCESS(status)) goto Exit;
    UdecxUsbEndpointSetWdfIoQueue(context->ControlEndpoint, context->ControlQueue);

    UDECX_USB_DEVICE_PLUG_IN_OPTIONS_INIT(&plugOptions);
    plugOptions.Usb20PortNumber = 1;
    status = UdecxUsbDevicePlugIn(context->UsbDevice, &plugOptions);
    if (NT_SUCCESS(status))
        status = VirKeyCreateGlobalControl(device, &context->GlobalControlDevice,
                                           &context->GlobalPdLinkCreated);

Exit:
    if (endpointInit != NULL) UdecxUsbEndpointInitFree(endpointInit);
    if (usbInit != NULL) UdecxUsbDeviceInitFree(usbInit);
    return status;
}
