#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>

/* Interactive-session test launcher. Creates SolidCAM suspended so a trace
 * can attach before its first device request, then waits for a resume flag. */
static void *volatile relocationAnchor = (void *)&relocationAnchor;
static volatile ULONGLONG loadConfigCookie = 0x2B992DDFA232ULL;
typedef struct VK_LOAD_CONFIG {
    DWORD Size;
    BYTE BeforeCookie[0x54];
    const volatile ULONGLONG *SecurityCookie;
    BYTE AfterCookie[0x148 - 0x60];
} VK_LOAD_CONFIG;
__declspec(allocate(".rdata")) const VK_LOAD_CONFIG _load_config_used = {
    0x148, {0}, &loadConfigCookie, {0}
};

void *memset(void *address, int value, size_t length)
{
    unsigned char *cursor = (unsigned char *)address;
    while (length-- != 0) *cursor++ = (unsigned char)value;
    return address;
}

static const WCHAR target[] =
    L"C:\\Program Files\\SolidCAM2024\\Solidcam\\Solidcam.exe";
static const WCHAR directory[] =
    L"C:\\Program Files\\SolidCAM2024\\Solidcam";
static const WCHAR pidFile[] = L"C:\\Temp\\VirKeySuspended.pid";
static const WCHAR resumeFile[] = L"C:\\Temp\\VirKeyResume.flag";

void mainCRTStartup(void)
{
    static const char hex[] = "0123456789ABCDEF";
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    HANDLE file;
    char pidText[8];
    DWORD written;
    DWORD i;
    BOOL resumed = FALSE;
    if (relocationAnchor == NULL) ExitProcess(2);
    DeleteFileW(pidFile);
    DeleteFileW(resumeFile);
    startup.cb = sizeof(startup);
    if (!CreateProcessW(target, NULL, NULL, NULL, FALSE, CREATE_SUSPENDED,
                        NULL, directory, &startup, &process)) ExitProcess(3);
    file = CreateFileW(pidFile, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                       FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        TerminateProcess(process.hProcess, 4);
        ExitProcess(4);
    }
    for (i = 0; i < 8; ++i)
        pidText[i] = hex[(process.dwProcessId >> (28 - 4*i)) & 15];
    WriteFile(file, pidText, sizeof(pidText), &written, NULL);
    CloseHandle(file);
    for (i = 0; i < 600; ++i) {
        if (GetFileAttributesW(resumeFile) != INVALID_FILE_ATTRIBUTES) {
            resumed = TRUE;
            break;
        }
        Sleep(100);
    }
    if (resumed) ResumeThread(process.hThread);
    else TerminateProcess(process.hProcess, 5);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    ExitProcess(resumed ? 0 : 5);
}
