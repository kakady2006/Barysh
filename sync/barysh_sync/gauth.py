"""Google service account sign-in without third-party packages: RS256 JWT signed with the
account's private key (PKCS#8 PEM from the JSON key file), exchanged for an access token."""

import base64
import hashlib
import json
import time
import urllib.parse
import urllib.request

SCOPE = "https://www.googleapis.com/auth/spreadsheets"
TOKEN_URI = "https://oauth2.googleapis.com/token"

# DER prefix of DigestInfo for SHA-256 (RFC 8017, section 9.2).
SHA256_PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")


class KeyFormatError(ValueError):
    pass


def _der_read(data, pos):
    """One DER element at pos: (tag, content bytes, next pos)."""
    tag = data[pos]
    length = data[pos + 1]
    pos += 2
    if length & 0x80:
        n = length & 0x7F
        length = int.from_bytes(data[pos:pos + n], "big")
        pos += n
    return tag, data[pos:pos + length], pos + length


def _der_sequence(data):
    tag, body, _ = _der_read(data, 0)
    if tag != 0x30:
        raise KeyFormatError("expected a DER sequence")
    out, pos = [], 0
    while pos < len(body):
        t, content, pos = _der_read(body, pos)
        out.append((t, content))
    return out


def private_key_from_pem(pem):
    """PKCS#8 'BEGIN PRIVATE KEY' (what Google issues) or PKCS#1 'BEGIN RSA PRIVATE KEY' -> (n, d)."""
    lines = [l for l in pem.strip().splitlines() if l and not l.startswith("-----")]
    der = base64.b64decode("".join(lines))
    items = _der_sequence(der)
    if len(items) >= 3 and items[1][0] == 0x30 and items[2][0] == 0x04:  # PKCS#8 wrapper
        items = _der_sequence(items[2][1])
    ints = [int.from_bytes(c, "big") for t, c in items if t == 0x02]
    if len(ints) < 4:
        raise KeyFormatError("not an RSA private key")
    _, n, _, d = ints[:4]
    return n, d


def sign_rs256(message, n, d):
    """RSASSA-PKCS1-v1_5 with SHA-256."""
    k = (n.bit_length() + 7) // 8
    t = SHA256_PREFIX + hashlib.sha256(message).digest()
    if k < len(t) + 11:
        raise KeyFormatError("key too short")
    em = b"\x00\x01" + b"\xff" * (k - len(t) - 3) + b"\x00" + t
    return pow(int.from_bytes(em, "big"), d, n).to_bytes(k, "big")


def _b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def make_jwt(key_info, now=None, scope=SCOPE):
    now = int(now or time.time())
    header = {"alg": "RS256", "typ": "JWT"}
    if key_info.get("private_key_id"):
        header["kid"] = key_info["private_key_id"]
    claims = {
        "iss": key_info["client_email"], "scope": scope, "aud": key_info.get("token_uri", TOKEN_URI),
        "iat": now, "exp": now + 3600,
    }
    signing_input = _b64url(json.dumps(header, separators=(",", ":")).encode()) + b"." + \
        _b64url(json.dumps(claims, separators=(",", ":")).encode())
    n, d = private_key_from_pem(key_info["private_key"])
    return (signing_input + b"." + _b64url(sign_rs256(signing_input, n, d))).decode()


def http_post_form(url, fields, timeout=30):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


class ServiceAccount:
    """Access tokens for a service account key file; refreshed a minute before they expire."""

    def __init__(self, key_file, post=http_post_form, clock=time.time):
        with open(key_file, encoding="utf-8") as f:
            self.info = json.load(f)
        self.post = post
        self.clock = clock
        self.token = None
        self.expires = 0

    @property
    def email(self):
        return self.info.get("client_email")

    def access_token(self):
        now = self.clock()
        if self.token and now < self.expires - 60:
            return self.token
        res = self.post(self.info.get("token_uri", TOKEN_URI), {
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": make_jwt(self.info, now),
        })
        self.token = res["access_token"]
        self.expires = now + int(res.get("expires_in", 3600))
        return self.token
