"""Generate KLAP test vectors from python-kasa so the Swift implementation can be
checked byte-for-byte. Fake credentials and fixed seeds only."""
import json

from kasa.credentials import Credentials
from kasa.transports.klaptransport import (
    KlapEncryptionSession,
    KlapTransport,
    KlapTransportV2,
)

creds = Credentials("user@example.com", "hunter2-Test")
local_seed = bytes(range(0x10, 0x20))
remote_seed = bytes(range(0xA0, 0xB0))

auth_v2 = KlapTransportV2.generate_auth_hash(creds)
auth_v1 = KlapTransport.generate_auth_hash(creds)

session = KlapEncryptionSession(local_seed, remote_seed, auth_v2)
initial_seq = session._seq
request = '{"method":"get_device_info","request_time_milis":1700000000000,"terminal_uuid":"dGVzdA=="}'
body, seq = session.encrypt(request)

# Device side: same session state, encrypts its reply at the same seq.
device = KlapEncryptionSession(local_seed, remote_seed, auth_v2)
device._seq = seq
device._generate_cipher()
reply = '{"error_code":0,"result":{"device_on":true,"brightness":42}}'
# encrypt() increments seq, so step back one first.
device._seq = seq - 1
reply_body, reply_seq = device.encrypt(reply)
assert reply_seq == seq
# python-kasa decrypt must read it with the client session
assert session.decrypt(reply_body) == reply

vectors = {
    "username": creds.username,
    "password": creds.password,
    "localSeed": local_seed.hex(),
    "remoteSeed": remote_seed.hex(),
    "authV2": auth_v2.hex(),
    "authV1": auth_v1.hex(),
    "handshake1V2": KlapTransportV2.handshake1_seed_auth_hash(local_seed, remote_seed, auth_v2).hex(),
    "handshake2V2": KlapTransportV2.handshake2_seed_auth_hash(local_seed, remote_seed, auth_v2).hex(),
    "handshake1V1": KlapTransport.handshake1_seed_auth_hash(local_seed, remote_seed, auth_v1).hex(),
    "handshake2V1": KlapTransport.handshake2_seed_auth_hash(local_seed, remote_seed, auth_v1).hex(),
    "key": session._key.hex(),
    "ivPrefix": session._iv.hex(),
    "initialSeq": initial_seq,
    "sig": session._sig.hex(),
    "request": request,
    "requestSeq": seq,
    "requestBody": body.hex(),
    "reply": reply,
    "replyBody": reply_body.hex(),
}
print(json.dumps(vectors, indent=2))
