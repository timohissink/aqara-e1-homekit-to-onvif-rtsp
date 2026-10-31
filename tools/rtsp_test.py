#!/usr/bin/env python3
"""RTSP DESCRIBE with and without Basic auth (what UniFi Protect does first).

Usage: RTSP_USER=rtspviewer RTSP_PASSWORD=... ./rtsp_test.py 192.168.1.31 /camera1 [8554]
Expected: without login -> 401, with login -> 200 OK + H264 SDP.
The password is read from the environment and never printed.
"""
import base64, os, socket, sys

host, path = sys.argv[1], sys.argv[2]
port = int(sys.argv[3]) if len(sys.argv) > 3 else 8554
user, pw = os.environ.get("RTSP_USER", ""), os.environ.get("RTSP_PASSWORD", "")

def describe(auth):
    s = socket.create_connection((host, port), timeout=10)
    req = f"DESCRIBE rtsp://{host}:{port}{path} RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\n"
    if auth:
        req += "Authorization: Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode() + "\r\n"
    s.sendall((req + "\r\n").encode())
    data = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
            if b"\r\n\r\n" in data:
                head, body = data.split(b"\r\n\r\n", 1)
                if b"Content-Length" not in head:
                    break
                n = int(head.split(b"Content-Length: ")[1].split(b"\r\n")[0])
                if len(body) >= n:
                    break
    except socket.timeout:
        pass
    s.close()
    return data.decode(errors="replace")

r = describe(False)
print("without login:", r.splitlines()[0] if r else "no answer")
r = describe(True)
print("with login   :", r.splitlines()[0] if r else "no answer")
for line in r.splitlines():
    if line.startswith(("m=", "a=rtpmap", "a=fmtp")):
        print("   ", line[:120])
