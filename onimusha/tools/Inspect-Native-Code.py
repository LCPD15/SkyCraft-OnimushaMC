"""Read-only disassembly of a bounded native method in the running local game.

No process writes, protection changes, remote calls, thread creation or injection.
Requires the optional capstone package in tools/disasm_packages.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
from pathlib import Path
import sys

ROOT = Path('G:/Onimusha_MC_mod')
sys.path.insert(0, str(ROOT / 'tools/disasm_packages'))
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pid', type=int, required=True)
    ap.add_argument('--address', type=lambda s: int(s, 0), required=True)
    ap.add_argument('--size', type=int, default=1024)
    ap.add_argument('--output', type=Path, required=True)
    a = ap.parse_args()
    if not 1 <= a.size <= 16384:
        raise ValueError('Read size must be between 1 and 16384 bytes')
    output = a.output.resolve()
    output.relative_to((ROOT / 'logs').resolve())
    k = c.WinDLL('kernel32', use_last_error=True)
    k.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
    k.OpenProcess.restype = w.HANDLE
    k.CloseHandle.argtypes = [w.HANDLE]
    k.QueryFullProcessImageNameW.argtypes = [w.HANDLE, w.DWORD, w.LPWSTR, c.POINTER(w.DWORD)]
    k.ReadProcessMemory.argtypes = [w.HANDLE, c.c_void_p, c.c_void_p, c.c_size_t, c.POINTER(c.c_size_t)]
    handle = k.OpenProcess(0x1000 | 0x10, False, a.pid)  # QUERY_LIMITED_INFORMATION | VM_READ
    if not handle:
        raise c.WinError(c.get_last_error())
    try:
        buf = c.create_unicode_buffer(32768)
        n = w.DWORD(len(buf))
        if not k.QueryFullProcessImageNameW(handle, 0, buf, c.byref(n)):
            raise c.WinError(c.get_last_error())
        expected = Path('F:/SteamLibrary/steamapps/common/OnimushaWotS/OnimushaWotS.exe')
        if Path(buf.value).resolve() != expected.resolve():
            raise ValueError(f'Unexpected process: {buf.value}')
        data = (c.c_ubyte * a.size)()
        count = c.c_size_t()
        if not k.ReadProcessMemory(handle, a.address, data, a.size, c.byref(count)) or count.value != a.size:
            raise c.WinError(c.get_last_error())
        raw = bytes(data)
    finally:
        k.CloseHandle(handle)
    text = f'PID {a.pid}, image {buf.value}, address {a.address:#x}\n'
    text += '\n'.join(f'{i.address:#x}: {i.bytes.hex():22s} {i.mnemonic:8s} {i.op_str}'
                      for i in Cs(CS_ARCH_X86, CS_MODE_64).disasm(raw, a.address)) + '\n'
    output.write_text(text, encoding='utf-8')
    output.with_suffix('.bytes.json').write_text(json.dumps({'pid': a.pid, 'image': buf.value,
        'address': a.address, 'hex': raw.hex()}, indent=2), encoding='utf-8')
    print(text)

if __name__ == '__main__':
    main()
