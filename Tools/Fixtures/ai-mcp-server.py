import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def answer(message):
    method = message.get("method")
    params = message.get("params", {})
    if method == "initialize":
        result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "fixture", "version": "1"}, "instructions": "FIXTURE_USAGE_NOTES"}
    elif method == "tools/list":
        result = {"tools": [{"name": "echo" if not params else "second", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}}]}
        if not params:
            result["nextCursor"] = "page2"
    elif method == "tools/call":
        args = params.get("arguments", {})
        if args.get("hang"):
            time.sleep(60)
        if os.environ.get("AI_TEST_LOG"):
            with open(os.environ["AI_TEST_LOG"], "a") as log:
                log.write(json.dumps(args) + "\n")
        result = {"content": [{"type": "text", "text": args.get("text", "echo")}], "isError": bool(args.get("fail"))}
    else:
        return {"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": "Unknown method"}}
    return {"jsonrpc": "2.0", "id": message["id"], "result": result}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        message = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path == "/redirect":
            self.send_response(307)
            self.send_header("Location", "/mcp")
            self.end_headers()
            return
        if "id" not in message or "method" not in message:
            self.send_response(202)
            self.end_headers()
            return
        if message["method"] != "initialize" and self.headers.get("Mcp-Session-Id") != "fixture-session":
            self.send_response(400)
            self.end_headers()
            return
        body = json.dumps(answer(message)).encode()
        self.send_response(200)
        self.send_header("Mcp-Session-Id", "fixture-session")
        if self.path in ("/sse", "/sse-cr"):
            ping = b'data: {"jsonrpc":"2.0","method":"ping","id":"server-ping"}\r\n\r\n'
            body = b': keepalive\r\n\r\n' + ping + b'data: ' + body + b'\r\n\r\n'
            if self.path == "/sse-cr":
                body = body.replace(b"\r\n", b"\r")
            self.send_header("Content-Type", "text/event-stream")
        else:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if "--http" in sys.argv:
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()
else:
    for line in sys.stdin:
        message = json.loads(line)
        if "id" in message and "method" in message:
            if message["method"] == "initialize":
                print(json.dumps({"jsonrpc": "2.0", "method": "ping", "id": "server-ping"}), flush=True)
            print(json.dumps(answer(message)), flush=True)
