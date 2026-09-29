#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <setupapi.h>
#include <shellapi.h>

/* A root-enumerated test node; the driver package is installed separately. */
static const GUID usbClass =
    {0x36fc9e60,0xc465,0x11cf,{0x80,0x56,0x44,0x45,0x53,0x54,0x00,0x00}};
static const GUID sentinelInterfaceA =
    {0x29db6d11,0xbc3c,0x11d7,{0xb4,0x7f,0x00,0xc0,0xdf,0xee,0x4d,0x8c}};
static const GUID sentinelInterfaceB =
    {0xbce9d0f1,0xf7db,0x11d7,{0xb4,0xbb,0x00,0xc0,0xdf,0xee,0x4d,0x8c}};
static const WCHAR hardwareId[] = L"ROOT\\VirKeyArm64";
void *memset(void *address, int value, size_t length)
{
    unsigned char *cursor = (unsigned char *)address;
    while (length-- != 0) *cursor++ = (unsigned char)value;
    return address;
}
/* Keep one absolute reference so the ARM64 PE has a relocation directory. */
static void *volatile relocationAnchor = (void *)&relocationAnchor;

/* Windows ARM64's user-mode loader requires a load-config security-cookie
 * address. Omitting it makes even a no-import executable fail with
 * STATUS_INVALID_IMAGE_FORMAT (0xC000007B) in the test guest. */
static volatile ULONGLONG loadConfigCookie = 0x2B992DDFA232ULL;
typedef struct VK_LOAD_CONFIG {
    DWORD Size;
    BYTE BeforeCookie[0x54];
    const volatile ULONGLONG *SecurityCookie;
    BYTE AfterCookie[0x148 - 0x60];
} VK_LOAD_CONFIG;
_Static_assert(sizeof(VK_LOAD_CONFIG) == 0x148, "load-config layout");
__declspec(allocate(".rdata")) const VK_LOAD_CONFIG _load_config_used = {
    0x148, {0}, &loadConfigCookie, {0}
};

static void print(const char *message)
{
    DWORD size = 0, written = 0;
    while (message[size] != 0) ++size;
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), message, size, &written, NULL);
}

static void print_error(const char *message)
{
    static const char digits[] = "0123456789ABCDEF";
    char line[] = " error=0x00000000\r\n";
    DWORD error = GetLastError();
    unsigned i;
    print(message);
    for (i = 0; i < 8; ++i)
        line[9 + i] = digits[(error >> ((7 - i) * 4)) & 15];
    print(line);
}

static void print_hex(const char *label, DWORD value)
{
    static const char digits[] = "0123456789ABCDEF";
    char line[] = " 00000000\r\n";
    unsigned i;
    print(label);
    for (i = 0; i < 8; ++i)
        line[1 + i] = digits[(value >> ((7 - i) * 4)) & 15];
    print(line);
}

static int probe_one_guid(const GUID *guid, const char *label)
{
    HDEVINFO set = SetupDiGetClassDevsW(guid, NULL, NULL,
                                       DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    SP_DEVICE_INTERFACE_DATA entry = {0};
    BYTE detailSpace[1024] = {0};
    PSP_DEVICE_INTERFACE_DETAIL_DATA_W detail =
        (PSP_DEVICE_INTERFACE_DETAIL_DATA_W)detailSpace;
    BYTE packet[304] = {0}, answer[304] = {0};
    const BYTE version[] = {1, 0, 0, 0, 0x0b, 0};
    const BYTE challenge[] = {0x1f,0x0e,0xf4,0x7e,0x89,0x68,0x7e,0x18};
    const BYTE expected[] = {0xf7,0x60,0x00,0xf1,0xd1,0xdd,0x42,0xc2};
    unsigned i;
    DWORD returned = 0;
    HANDLE handle;
    BOOL ok;
    int result = 2;
    int failures = 0;
    if (set == INVALID_HANDLE_VALUE) {
        print_error("enumerate interface");
        return result;
    }
    entry.cbSize = sizeof(entry);
    if (!SetupDiEnumDeviceInterfaces(set, NULL, guid, 0, &entry)) {
        print_error("interface not found");
        goto Exit;
    }
    detail->cbSize = sizeof(*detail);
    if (!SetupDiGetDeviceInterfaceDetailW(set, &entry, detail,
                                           sizeof(detailSpace), NULL, NULL)) {
        print_error("read interface path");
        goto Exit;
    }
    handle = CreateFileW(detail->DevicePath, GENERIC_READ | GENERIC_WRITE,
                         FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                         OPEN_EXISTING, 0, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        print_error("open interface");
        goto Exit;
    }
    print(label);
    print(" open\r\n");
    ok = DeviceIoControl(handle, 0x9C402450, (PVOID)version,
                         sizeof(version), answer, 6, &returned, NULL);
    if (ok && returned == 6)
        print_hex("version word", (DWORD)answer[2] | ((DWORD)answer[3] << 8) |
                              ((DWORD)answer[4] << 16) | ((DWORD)answer[5] << 24));
    else { print_error("version IOCTL"); ++failures; }

    packet[0] = 3; packet[1] = 0x58; packet[6] = 4;
    packet[8] = 0x8f; packet[9] = 0x4c;
    packet[12] = 0x3c; packet[13] = 0x74;
    ok = DeviceIoControl(handle, 0x9C402458, packet, 256,
                         answer, 256, &returned, NULL);
    if (ok && returned == 256)
        print_hex("initial fields", (DWORD)answer[16] |
                     ((DWORD)answer[130] << 8) | ((DWORD)answer[132] << 16) |
                     ((DWORD)answer[254] << 24));
    else { print_error("initial IOCTL"); ++failures; }

    packet[24] = 0x17;
    ok = DeviceIoControl(handle, 0x9C402458, packet, 304,
                         answer, 304, &returned, NULL);
    if (ok && returned == 304)
        print_hex("data first word", (DWORD)answer[256] |
                  ((DWORD)answer[257] << 8) | ((DWORD)answer[258] << 16) |
                  ((DWORD)answer[259] << 24));
    else { print_error("data IOCTL"); ++failures; }

    packet[24] = 0x1d; packet[132] = 0x0a;
    ok = DeviceIoControl(handle, 0x9C402458, packet, 256,
                         answer, 256, &returned, NULL);
    if (ok && returned == 256)
        print_hex("serial number", (DWORD)answer[16] |
                  ((DWORD)answer[17] << 8) | ((DWORD)answer[130] << 16) |
                  ((DWORD)answer[131] << 24));
    else { print_error("serial IOCTL"); ++failures; }

    packet[24] = 0x3d; packet[256] = 1;
    ok = DeviceIoControl(handle, 0x9C402458, packet, 264,
                         answer, 264, &returned, NULL);
    if (ok) {
        print("invalid crypto command unexpectedly accepted\r\n");
        ++failures;
    } else if (GetLastError() == ERROR_NOT_SUPPORTED) {
        print_error("invalid crypto command rejected as expected");
    } else {
        print_error("challenge rejection error");
        ++failures;
    }
    packet[25] = 1;
    for (i = 0; i != 8; ++i) packet[256 + i] = challenge[i];
    ok = DeviceIoControl(handle, 0x9C402458, packet, 264,
                         answer, 264, &returned, NULL);
    if (ok && returned == 264) {
        for (i = 0; i != 8; ++i)
            if (answer[256 + i] != expected[i]) break;
        if (i == 8) print("SC decode matches independent x64 response\r\n");
        else { print("SC decode mismatch\r\n"); ++failures; }
    } else { print_error("SC decode IOCTL"); ++failures; }
    CloseHandle(handle);
    result = failures == 0 ? 0 : 2;
Exit:
    SetupDiDestroyDeviceInfoList(set);
    return result;
}

static int probe(void)
{
    int a = probe_one_guid(&sentinelInterfaceA, "interface A");
    int b = probe_one_guid(&sentinelInterfaceB, "interface B");
    return a == 0 && b == 0 ? 0 : 2;
}

static BOOL is_target(HDEVINFO set, SP_DEVINFO_DATA *info)
{
    WCHAR ids[512];
    DWORD type = 0, required = 0;
    const WCHAR *id;
    if (!SetupDiGetDeviceRegistryPropertyW(set, info, SPDRP_HARDWAREID,
                                           &type, (PBYTE)ids, sizeof(ids),
                                           &required) || type != REG_MULTI_SZ)
        return FALSE;
    for (id = ids; *id != 0; id += lstrlenW(id) + 1)
        if (lstrcmpiW(id, hardwareId) == 0) return TRUE;
    return FALSE;
}

static BOOL find_target(HDEVINFO set, SP_DEVINFO_DATA *found)
{
    DWORD index;
    for (index = 0;; ++index) {
        SP_DEVINFO_DATA info = {0};
        info.cbSize = sizeof(info);
        if (!SetupDiEnumDeviceInfo(set, index, &info)) return FALSE;
        if (is_target(set, &info)) {
            *found = info;
            return TRUE;
        }
    }
}

static int create_node(void)
{
    HDEVINFO all = SetupDiGetClassDevsW(NULL, NULL, NULL, DIGCF_ALLCLASSES);
    HDEVINFO set;
    SP_DEVINFO_DATA info = {0};
    static const WCHAR ids[] = L"ROOT\\VirKeyArm64\0\0";
    BOOL ok;
    if (all == INVALID_HANDLE_VALUE) {
        print_error("enumerate devices"); return 2;
    }
    if (find_target(all, &info)) {
        SetupDiDestroyDeviceInfoList(all);
        print("VirKeyArm64 node already exists\r\n"); return 0;
    }
    SetupDiDestroyDeviceInfoList(all);

    set = SetupDiCreateDeviceInfoList(&usbClass, NULL);
    if (set == INVALID_HANDLE_VALUE) {
        print_error("create device set"); return 2;
    }
    info.cbSize = sizeof(info);
    ok = SetupDiCreateDeviceInfoW(set, L"VirKeyArm64", &usbClass,
                                   L"VirKeyArm64 Virtual USB Controller",
                                   NULL, DICD_GENERATE_ID, &info);
    if (!ok) print_error("create root node");
    if (ok) {
        ok = SetupDiSetDeviceRegistryPropertyW(set, &info, SPDRP_HARDWAREID,
                                                (const BYTE *)ids, sizeof(ids));
        if (!ok) print_error("set hardware ID");
    }
    if (ok) {
        ok = SetupDiCallClassInstaller(DIF_REGISTERDEVICE, set, &info);
        if (!ok) print_error("register root node");
    }
    SetupDiDestroyDeviceInfoList(set);
    if (ok) print("VirKeyArm64 node created\r\n");
    return ok ? 0 : 2;
}

static int remove_node(void)
{
    HDEVINFO set = SetupDiGetClassDevsW(NULL, NULL, NULL, DIGCF_ALLCLASSES);
    SP_DEVINFO_DATA info = {0};
    BOOL ok;
    if (set == INVALID_HANDLE_VALUE) {
        print_error("enumerate devices"); return 2;
    }
    if (!find_target(set, &info)) {
        SetupDiDestroyDeviceInfoList(set);
        print("VirKeyArm64 node already absent\r\n"); return 0;
    }
    ok = SetupDiCallClassInstaller(DIF_REMOVE, set, &info);
    if (!ok) print_error("remove root node");
    SetupDiDestroyDeviceInfoList(set);
    if (ok) print("VirKeyArm64 node removed\r\n");
    return ok ? 0 : 2;
}

void mainCRTStartup(void)
{
    int count = 0, result = 2;
    if (relocationAnchor == NULL) ExitProcess(2);
    LPWSTR *args = CommandLineToArgvW(GetCommandLineW(), &count);
    if (args != NULL && count == 2) {
        if (lstrcmpiW(args[1], L"create") == 0) result = create_node();
        else if (lstrcmpiW(args[1], L"remove") == 0) result = remove_node();
        else if (lstrcmpiW(args[1], L"probe") == 0) result = probe();
    }
    if (result == 2 && (args == NULL || count != 2))
        print("Usage: VirKeyNode.exe create|remove|probe\r\n");
    if (args != NULL) LocalFree(args);
    ExitProcess(result);
}
