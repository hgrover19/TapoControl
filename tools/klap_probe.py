#!/usr/bin/env python3
"""Phase 0 check: talk KLAP to your Tapo bulbs from Terminal, no installs needed.

Uses only the Python standard library plus the `openssl` command that ships with
macOS (for AES-128-CBC). Terminal isn't subject to macOS Local Network privacy,
so this tests the protocol and your login on their own, separately from the app.

Usage:
    python3 tools/klap_probe.py                      # state of both default bulbs
    python3 tools/klap_probe.py 192.168.2.18 state
    python3 tools/klap_probe.py 192.168.2.18 off
    python3 tools/klap_probe.py 192.168.2.18 on

Your email and password are read with getpass (or TAPO_EMAIL / TAPO_PASSWORD) and are
never written anywhere. If the login is rejected, the script stops instead of retrying:
repeated failed logins can lock a bulb for a while.
"""
from __future__ import annotations

import base64
import getpass
import hashlib
import json
import os
import secrets
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request

DEFAULT_HOSTS = ["192.168.2.20", "192.168.2.18"]


def sha256(b: bytes) -> bytes:
    return hashlib.sha256(b).digest()


def aes_cbc(encrypt: bool, data: bytes, key: bytes, iv: bytes) -> bytes:
    try:  # Use the cryptography package if it happens to be installed.
        from cryptography.hazmat.primitives import padding
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

        cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
        if encrypt:
            padder = padding.PKCS7(128).padder()
            data = padder.update(data) + padder.finalize()
            op = cipher.encryptor()
            return op.update(data) + op.finalize()
        op = cipher.decryptor()
        raw = op.update(data) + op.finalize()
        unpadder = padding.PKCS7(128).unpadder()
        return unpadder.update(raw) + unpadder.finalize()
    except ImportError:
        args = ["openssl", "enc", "-aes-128-cbc", "-K", key.hex(), "-iv", iv.hex()]
        if not encrypt:
            args.append("-d")
        return subprocess.run(args, input=data, capture_output=True, check=True).stdout


class KlapError(Exception):
    pass


class Klap:
    def __init__(self, host: str, username: str, password: str):
        self.host = host
        self.auth_v2 = sha256(hashlib.sha1(username.encode()).digest() + hashlib.sha1(password.encode()).digest())
        md5 = lambda b: hashlib.md5(b).digest()  # noqa: E731
        self.auth_v1 = md5(md5(username.encode()) + md5(password.encode()))
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        self.terminal_uuid = base64.b64encode(hashlib.md5(os.urandom(16)).digest()).decode()

    def _post(self, path: str, body: bytes, cookie: str | None = None):
        req = urllib.request.Request(f"http://{self.host}/app/{path}", data=body, method="POST")
        req.add_header("Content-Type", "application/octet-stream")
        if cookie:
            req.add_header("Cookie", cookie)
        try:
            with self.opener.open(req, timeout=5) as resp:
                return resp.status, resp.read(), resp.headers
        except urllib.error.HTTPError as e:
            return e.code, e.read(), e.headers
        except (urllib.error.URLError, OSError) as e:
            raise KlapError(f"can't reach {self.host}: {e}") from None

    def handshake(self):
        local_seed = secrets.token_bytes(16)
        status, data, headers = self._post("handshake1", local_seed)
        if status != 200:
            raise KlapError(f"handshake1 HTTP {status}. If 403: the bulb isn't accepting KLAP. "
                            "Toggle Third-Party Compatibility off and on in the Tapo app.")
        if len(data) != 48:
            raise KlapError(f"handshake1 returned {len(data)} bytes, expected 48")
        remote_seed, server_hash = data[:16], data[16:]
        if sha256(local_seed + remote_seed + self.auth_v2) == server_hash:
            self.version, auth = "v2", self.auth_v2
            proof = sha256(remote_seed + local_seed + auth)
        elif sha256(local_seed + self.auth_v1) == server_hash:
            self.version, auth = "v1", self.auth_v1
            proof = sha256(remote_seed + auth)
        else:
            raise KlapError("the bulb rejected the email/password (stopping, not retrying)")
        cookies = {}
        for part in (headers.get("Set-Cookie") or "").replace(",", ";").split(";"):
            if "=" in part:
                k, v = part.split("=", 1)
                cookies[k.strip()] = v.strip()
        if "TP_SESSIONID" not in cookies:
            raise KlapError("no TP_SESSIONID cookie in handshake1")
        self.cookie = f"TP_SESSIONID={cookies['TP_SESSIONID']}"
        status, _, _ = self._post("handshake2", proof, self.cookie)
        if status != 200:
            raise KlapError(f"handshake2 HTTP {status}")
        material = local_seed + remote_seed + auth
        self.key = sha256(b"lsk" + material)[:16]
        full_iv = sha256(b"iv" + material)
        self.iv, self.seq = full_iv[:12], struct.unpack(">l", full_iv[-4:])[0]
        self.sig = sha256(b"ldk" + material)[:28]

    def request(self, method: str, params: dict | None = None) -> dict:
        payload = {"method": method, "request_time_milis": int(time.time() * 1000), "terminal_uuid": self.terminal_uuid}
        if params is not None:
            payload["params"] = params
        self.seq += 1
        seq_bytes = struct.pack(">l", self.seq)
        iv = self.iv + seq_bytes
        ct = aes_cbc(True, json.dumps(payload).encode(), self.key, iv)
        body = sha256(self.sig + seq_bytes + ct) + ct
        status, data, _ = self._post(f"request?seq={self.seq}", body, self.cookie)
        if status != 200:
            raise KlapError(f"request HTTP {status}")
        reply = json.loads(aes_cbc(False, data[32:], self.key, iv))
        if reply.get("error_code") != 0:
            raise KlapError(f"device error {reply.get('error_code')}")
        return reply.get("result", {})


def main(argv):
    hosts = [a for a in argv if a[0].isdigit() or ":" in a] or DEFAULT_HOSTS
    action = next((a for a in argv if a in ("state", "on", "off")), "state")
    username = os.environ.get("TAPO_EMAIL") or input("Tapo email: ").strip()
    password = os.environ.get("TAPO_PASSWORD") or getpass.getpass("Tapo password: ")
    ok = True
    for host in hosts:
        print(f"\n== {host}")
        try:
            k = Klap(host, username, password)
            k.handshake()
            print(f"KLAP {k.version} handshake OK")
            if action in ("on", "off"):
                k.request("set_device_info", {"device_on": action == "on"})
                print(f"sent device_on={action == 'on'}")
            info = k.request("get_device_info")
            nickname = base64.b64decode(info.get("nickname", "")).decode(errors="replace")
            print(f"model={info.get('model')} fw={info.get('fw_ver')} name={nickname!r}")
            print(f"device_on={info.get('device_on')} brightness={info.get('brightness')} "
                  f"color_temp={info.get('color_temp')} hue={info.get('hue')} saturation={info.get('saturation')} "
                  f"color_temp_range={info.get('color_temp_range')}")
        except KlapError as e:
            ok = False
            print(f"FAILED: {e}")
            if "rejected the email" in str(e):
                break  # don't hammer the next bulb with the same wrong login
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
