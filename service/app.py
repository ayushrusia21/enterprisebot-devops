import json, os, socket, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG_DIR = os.environ.get("CONFIG_DIR", "/etc/app-config")

def setting(name, default):
    # Prefer mounted ConfigMap file (follows live edits), fall back to env var
    try:
        with open(os.path.join(CONFIG_DIR, name)) as f:
            v = f.read().strip()
            if v:
                return v
    except OSError:
        pass
    return os.environ.get(name, default)

class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/":
            self._send(200, {"app": setting("APP_NAME", "unset"),
                             "version": setting("VERSION", "unset"),
                             "pod": socket.gethostname()})
        elif path == "/healthz":
            self._send(200, b"ok", "text/plain")
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
