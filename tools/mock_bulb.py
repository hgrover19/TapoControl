"""A fake KLAP v2 bulb for testing clients. Device-side crypto comes from python-kasa,
so it is an independent check of the client implementation."""
import hashlib
import json
import secrets
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

from kasa.credentials import Credentials
from kasa.transports.klaptransport import KlapEncryptionSession, KlapTransportV2

AUTH = KlapTransportV2.generate_auth_hash(Credentials("user@example.com", "hunter2-Test"))
STATE = {"device_on": False, "brightness": 50, "hue": 0, "saturation": 0, "color_temp": 2700,
         "color_temp_range": [2500, 6500], "model": "L530", "fw_ver": "1.4.2 mock",
         "nickname": "TW9jayBCdWxi"}
SESSIONS = {}
LOG = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _reply(self, code, body=b"", headers=()):
        self.send_response(code)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        url = urlparse(self.path)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        cookie = (self.headers.get("Cookie") or "").replace("TP_SESSIONID=", "")
        LOG.append(url.path)
        if url.path == "/app/handshake1":
            rs = secrets.token_bytes(16)
            sid = secrets.token_hex(8)
            SESSIONS[sid] = {"ls": body, "rs": rs, "ok": False}
            proof = hashlib.sha256(body + rs + AUTH).digest()
            return self._reply(200, rs + proof, [("Set-Cookie", f"TP_SESSIONID={sid};TIMEOUT=86400")])
        sess = SESSIONS.get(cookie)
        if not sess:
            return self._reply(403)
        if url.path == "/app/handshake2":
            expected = hashlib.sha256(sess["rs"] + sess["ls"] + AUTH).digest()
            if body != expected:
                return self._reply(403)
            sess["ok"] = True
            sess["enc"] = KlapEncryptionSession(sess["ls"], sess["rs"], AUTH)
            return self._reply(200)
        if url.path == "/app/request" and sess["ok"]:
            seq = int(parse_qs(url.query)["seq"][0])
            enc = sess["enc"]
            sig = hashlib.sha256(enc._sig + seq.to_bytes(4, "big", signed=True) + body[32:]).digest()
            if sig != body[:32]:
                return self._reply(403)
            enc._seq = seq
            enc._generate_cipher()
            req = json.loads(enc.decrypt(body))
            if req["method"] == "set_device_info":
                STATE.update(req["params"])
                reply = {"error_code": 0}
            elif req["method"] == "get_device_info":
                reply = {"error_code": 0, "result": STATE}
            else:
                reply = {"error_code": -1}
            enc._seq = seq - 1
            out, _ = enc.encrypt(json.dumps(reply))
            return self._reply(200, out)
        return self._reply(404)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
