#!/bin/bash
# Verify the OpenSSL 3.5 migration against a rootfs staging tree.
# Usage: verify-openssl3.sh <rootfs-dir>
set -u
ROOTFS="${1:?usage: verify-openssl3.sh <rootfs-dir>}"
fail=0

echo "== 1. No ELF may reference libssl.so.1.1 / libcrypto.so.1.1"
stale=$(find "$ROOTFS" -type f \( -perm -u+x -o -name "*.so*" \) | while read -r f; do
  file -b "$f" 2>/dev/null | grep -q ELF || continue
  readelf -d "$f" 2>/dev/null | grep -qE "NEEDED.*(libssl\.so\.1\.1|libcrypto\.so\.1\.1)" && echo "$f"
done)
if [ -n "$stale" ]; then echo "FAIL — stale 1.1 linkage:"; echo "$stale"; fail=1; else echo "OK"; fi

echo "== 2. Old library files must be gone, new ones present"
for lib in libssl.so.1.1 libcrypto.so.1.1; do
  found=$(find "$ROOTFS" -name "$lib" | head -1)
  [ -n "$found" ] && { echo "FAIL — $found still in image"; fail=1; }
done
for lib in libssl.so.3 libcrypto.so.3; do
  found=$(find "$ROOTFS" -name "$lib" | head -1)
  [ -z "$found" ] && { echo "FAIL — $lib missing"; fail=1; }
done
[ $fail -eq 0 ] && echo "OK"

echo "== 3. Product daemons link .so.3"
for bin in usr/sbin/media-gateway usr/sbin/intelligence_edge_opcua; do
  if [ -f "$ROOTFS/$bin" ]; then
    readelf -d "$ROOTFS/$bin" | grep -qE "NEEDED.*libssl\.so\.3" && echo "OK $bin" || { echo "FAIL — $bin does not link libssl.so.3"; fail=1; }
  else
    echo "MISSING $bin (not yet installed into this tree?)"; fail=1
  fi
done

echo "== 4. open62541 is 1.3.15"
so=$(find "$ROOTFS" -name "libopen62541.so.1.3.*" | head -1)
case "$so" in *1.3.15*) echo "OK $so";; *) echo "FAIL — found: ${so:-none}"; fail=1;; esac

echo "== 5. ADR-151 leftovers absent (nginx)"
if find "$ROOTFS" \( -name nginx -o -path "*etc/nginx*" \) | grep -q .; then
  echo "FAIL — nginx artifacts still present"; fail=1
else echo "OK"; fi

exit $fail
