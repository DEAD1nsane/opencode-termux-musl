#!/usr/bin/env python3
"""Simple HTTP proxy for opencode on Android.
Binds to 127.0.0.1:8080 and forwards all requests to the target API.
"""
import http.server
import urllib.request
import ssl
import sys
import os

TARGET = os.environ.get("PROXY_TARGET", "https://opencode.ai")
PORT = int(os.environ.get("PROXY_PORT", "8080"))

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_request(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length) if length else None

        url = TARGET + self.path
        req = urllib.request.Request(url, data=body, method=self.command)
        for key, val in self.headers.items():
            if key.lower() not in ('host', 'proxy-connection'):
                req.add_header(key, val)

        ctx = ssl.create_default_context()
        try:
            resp = urllib.request.urlopen(req, context=ctx, timeout=60)
            self.send_response(resp.status)
            for key, val in resp.getheaders():
                if key.lower() not in ('transfer-encoding',):
                    self.send_header(key, val)
            self.end_headers()
            self.wfile.write(resp.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for key, val in e.headers.items():
                if key.lower() not in ('transfer-encoding',):
                    self.send_header(key, val)
            self.end_headers()
            if e.readable():
                self.wfile.write(e.read())
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(str(e).encode())

    do_POST = do_request
    do_PUT = do_request
    do_PATCH = do_request
    do_DELETE = do_request

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'ok')
        else:
            self.do_request()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

    def log_message(self, format, *args):
        sys.stderr.write(f"[proxy] {args[0]}\n")

if __name__ == '__main__':
    import logging
    logging.disable(logging.CRITICAL)
    server = http.server.HTTPServer(('127.0.0.1', PORT), ProxyHandler)
    server.serve_forever()

