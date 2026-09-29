// Read-only API observation in the running x64 Sentinel service.
// Hook only Win32 device calls and cap copied buffers and event count.
let sent = 0;
const maxEvents = 2000;
const ntdll = Process.getModuleByName('ntdll.dll');
const getLastError = new NativeFunction(
  Process.getModuleByName('KERNELBASE.dll').getExportByName('GetLastError'),
  'uint', []);
const queryObject = new NativeFunction(ntdll.getExportByName('NtQueryObject'),
  'int', ['pointer', 'int', 'pointer', 'ulong', 'pointer']);
function ntFileName(attributes) {
  try {
    const namePtr = attributes.add(Process.pointerSize === 8 ? 16 : 8)
      .readPointer();
    if (namePtr.isNull()) return '';
    const length = namePtr.readU16();
    const buffer = namePtr.add(Process.pointerSize === 8 ? 8 : 4)
      .readPointer();
    return buffer.isNull() ? '' : buffer.readUtf16String(length / 2);
  } catch (_) { return ''; }
}
function objectName(handle) {
  try {
    const info = Memory.alloc(4096), returned = Memory.alloc(4);
    if (queryObject(handle, 1, info, 4096, returned) !== 0) return '';
    const size = info.readU16(), pointer = info.add(Process.pointerSize).readPointer();
    return pointer.isNull() ? '' : pointer.readUtf16String(size / 2);
  } catch (_) { return ''; }
}
function bytes(p, n) {
  if (p.isNull() || n === 0) return '';
  try {
    const raw = p.readByteArray(Math.min(n, 512));
    return Array.from(new Uint8Array(raw), b => b.toString(16).padStart(2, '0')).join('');
  } catch (e) { return 'unreadable:' + e; }
}
function emit(obj) {
  if (sent++ < maxEvents) send(obj);
}
const base = Process.getModuleByName('KERNELBASE.dll');
Interceptor.attach(ntdll.getExportByName('NtCreateFile'), {
  onEnter(args) {
    this.path = ntFileName(args[2]);
    this.outputHandle = args[0];
    this.interesting = /usb#|hasp|usbpdcom|fentedev|vid_0529/i.test(this.path);
  },
  onLeave(ret) {
    if (!this.interesting) return;
    let handle = '';
    let object = '';
    if (ret.toInt32() >= 0) {
      try {
        handle = this.outputHandle.readPointer().toString();
        object = objectName(ptr(handle));
      } catch (_) {}
    }
    emit({kind:'nt-open', path:this.path, status:ret.toString(), handle,
          object});
  }
});
Interceptor.attach(base.getExportByName('CreateFileW'), {
  onEnter(args) {
    this.path = args[0].isNull() ? '' : args[0].readUtf16String();
  },
  onLeave(ret) {
    const interestingPath = this.path &&
      /usbpdcom|fentedev|vid_0529|usb#hasp|7ab02247|29db6d11|bce9d0f1/i.test(this.path);
    if (ret.equals(ptr(-1))) {
      if (interestingPath)
        emit({kind:'open-failed', path:this.path, error:getLastError()});
      return;
    }
    const name = objectName(ret);
    if (name.toLowerCase().includes('00000109') ||
        name.toLowerCase().includes('0000010a') ||
        name.toLowerCase().includes('fnt0') ||
        interestingPath)
      emit({kind:'open', path:this.path, handle:ret.toString(), object:name});
  }
});
Interceptor.attach(base.getExportByName('DeviceIoControl'), {
  onEnter(args) {
    this.handle = args[0].toString();
    this.code = args[1].toUInt32();
    this.skip = (this.code >>> 24) !== 0x9c;
    if (this.skip) return;
    this.object = objectName(args[0]);
    this.input = args[2];
    this.inLength = args[3].toUInt32();
    this.output = args[4];
    this.outLength = args[5].toUInt32();
    this.returned = args[6];
    this.inHex = bytes(this.input, this.inLength);
  },
  onLeave(ret) {
    if (this.skip) return;
    let n = 0;
    try { if (!this.returned.isNull()) n = this.returned.readU32(); } catch (_) {}
    emit({kind:'ioctl', handle:this.handle, object:this.object,
      code:'0x'+this.code.toString(16),
      inLength:this.inLength, outLength:this.outLength, input:this.inHex,
      ok:!ret.isNull(), returned:n, output:bytes(this.output,
        Math.min(this.outLength, n))});
  }
});
emit({kind:'ready', arch:Process.arch, pid:Process.id});
