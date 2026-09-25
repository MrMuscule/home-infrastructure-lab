from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import psycopg


def get_db_connection():
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
    )


class Handler(BaseHTTPRequestHandler):

    def do_POST(self):
        if self.path != "/telemetry":
            self.send_response(404)
            self.end_headers()
            return

        try:
            content_length = int(self.headers["Content-Length"])
            body = self.rfile.read(content_length)
            data = json.loads(body)

            conn = get_db_connection()

            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO telemetry
                    (server_name, metric_name, metric_value)
                    VALUES (%s, %s, %s)
                    """,
                    (
                        data["server_name"],
                        data["metric_name"],
                        data["metric_value"],
                    ),
                )

            conn.commit()
            conn.close()

            response = {
                "status": "ok",
                "message": "telemetry stored"
            }

            self.send_response(201)

        except Exception:
            response = {
                "status": "error",
                "message": "invalid telemetry data"
            }

            self.send_response(400)

        self.send_header("Content-Type", "application/json")
        self.end_headers()

        self.wfile.write(json.dumps(response).encode())

    def do_GET(self):

        if self.path == "/health/db":
            try:
                conn = get_db_connection()
                conn.close()

                response = {
                    "status": "ok",
                    "database": "connected"
                }

                self.send_response(200)

            except Exception:
                response = {
                    "status": "error",
                    "database": "unavailable"
                }

                self.send_response(503)

            self.send_header("Content-Type", "application/json")
            self.end_headers()

            self.wfile.write(json.dumps(response).encode())
            return

        if self.path == "/health":
            response = {
                "status": "ok",
                "server": "web02"
            }

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()

            self.wfile.write(json.dumps(response).encode())
            return

        self.send_response(404)
        self.end_headers()


server = HTTPServer((os.getenv("API_HOST", "0.0.0.0"), int(os.getenv("API_PORT", "8081"))), Handler)
print("API started on 10.10.10.2:8081")
server.serve_forever()
