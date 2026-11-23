#!/usr/bin/env python3
# Run ISOLATED:  python3 -I patch_hidl_descriptor.py <in> <out>
#
# In-place HIDL/AIDL interface-descriptor renamer for Oplus biometrics blobs.
#
# Purpose
# -------
# ColorOS forks an AOSP HIDL interface and renames only the package, e.g.
#   AOSP :  android.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint
#   Oplus:  vendor.oplus.hardware.biometrics.fingerprint@2.1::IBiometricsFingerprint
# The descriptor is the binder interface token, so an AOSP GSI framework that
# transacts the AOSP token never reaches the oplus service. Rewriting the
# descriptor CONSTANT so the service both registers and answers to the AOSP
# name bridges the gap -- IF the fork is a clean rename (same method table).
#
# The descriptor constant lives in the generated INTERFACE LIBRARY, not in the
# -service executable:
#   /odm/lib64/vendor.oplus.hardware.biometrics.fingerprint@2.1.so
# That .so is the file to pass here. (The -service binary only *imports*
# IBiometricsFingerprint::descriptor from the .so, so patching it does nothing.)
#
# Safety / in-place rule
# ----------------------
# The AOSP package token is 5 bytes SHORTER than the oplus one
# ("vendor.oplus.hardware..." 48B vs "android.hardware..." 43B for @2.1), so a
# descriptor string can be rewritten WITHIN ITS OWN BYTE SPAN: write the shorter
# string, its NUL terminator, then NUL-pad the freed tail. File size is
# unchanged and no other byte moves, so every ELF offset / relocation stays
# valid.
#
# This script ONLY touches human-readable descriptor strings. It refuses to
# touch:
#   - shared-library names (strings ending in ".so")     -> those are correct
#   - C++ mangled symbols (strings containing "_ZN"/"6vendor5oplus") -> break relocs
# so it is safe to run blindly over a whole binary.

import sys

# (old_package_prefix, new_package_prefix). Prefix only -- version + "::IFace"
# tail is preserved. new must be SHORTER than old (in-place shrink).
RULES = [
    (b"vendor.oplus.hardware.biometrics.fingerprint",
     b"android.hardware.biometrics.fingerprint"),
    (b"vendor.oplus.hardware.biometrics.face",
     b"android.hardware.biometrics.face"),
]


def c_string_span(buf, pos):
    """Return (start, end_exclusive_of_NUL) of the NUL-terminated C string that
    contains byte offset `pos`. start = byte after previous NUL; end = index of
    the terminating NUL."""
    start = buf.rfind(b"\x00", 0, pos) + 1  # 0 if none -> start of file
    end = buf.find(b"\x00", pos)
    if end == -1:
        end = len(buf)
    return start, end


def is_patch_target(s):
    """s is the full C string (no NUL). True only for a bare descriptor/package
    token, never a .so name or a mangled symbol."""
    if s.endswith(b".so"):
        return False            # library name -- leave alone
    if b"_Z" in s or s.startswith(b"_"):
        return False            # mangled C++ symbol -- leave alone
    # must be printable ASCII only (descriptors are)
    if any(c < 0x20 or c > 0x7e for c in s):
        return False
    return True


def patch(buf):
    changes = []
    for old, new in RULES:
        assert len(new) < len(old), "new prefix must be shorter for in-place patch"
        delta = len(old) - len(new)
        search = 0
        while True:
            i = buf.find(old, search)
            if i == -1:
                break
            search = i + 1
            start, end = c_string_span(buf, i)
            s = bytes(buf[start:end])
            if not is_patch_target(s):
                continue
            # the token must be the package *prefix* of this descriptor string,
            # i.e. appear at the very start of the C string.
            if not s.startswith(old):
                continue
            new_s = new + s[len(old):]
            # write shorter string in place, NUL-terminate, NUL-pad freed tail
            buf[start:end] = new_s + b"\x00" * (len(s) - len(new_s))
            # end byte was the original terminator; it stays NUL. We padded
            # exactly `delta` bytes before it -> span length unchanged.
            changes.append((start, s.decode(), new_s.decode(), delta))
    return changes


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: python3 -I patch_hidl_descriptor.py <in> <out>")
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, "rb") as f:
        buf = bytearray(f.read())
    orig_len = len(buf)
    changes = patch(buf)
    assert len(buf) == orig_len, "file size changed -- aborting"
    with open(dst, "wb") as f:
        f.write(buf)
    if not changes:
        print("NO descriptor strings matched. Nothing patched.")
        print("(If this was a -service binary, that is expected: the descriptor")
        print(" lives in the @x.y.so interface library, not the executable.)")
        return
    print(f"patched {len(changes)} descriptor string(s), size unchanged "
          f"({orig_len} bytes):")
    for off, a, b, d in changes:
        print(f"  @0x{off:x}  -{d}B")
        print(f"      from: {a}")
        print(f"      to:   {b}")


if __name__ == "__main__":
    main()
