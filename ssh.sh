#!/bin/bash

echo "🛠 Memulai instalasi SSH WebSocket Server..."

# 1. Pastikan Python terinstall
apt update -y
apt install -y python3 -y

# 2. Hapus script lama jika ada
rm -f /etc/sshws/ws-server.py

# 3. Buat direktori dan script baru
mkdir -p /etc/sshws

cat << 'EOF' > /etc/sshws/ws-server.py
#!/usr/bin/env python3
import socket, threading, os

LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 80
BUFFER_SIZE = 1024

def handle(client_socket):
    try:
        req = b""
        while b"\r\n\r\n" not in req:
            chunk = client_socket.recv(BUFFER_SIZE)
            if not chunk:
                break
            req += chunk

        header = req.decode(errors="ignore")
        print("=== HEADER DITERIMA ===")
        print(header)
        print("========================")

        if "upgrade" in header.lower() and "websocket" in header.lower():
            response = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n\r\n"
            )
            client_socket.send(response.encode())

            try:
                target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                target.connect(("127.0.0.1", 22))

                def forward(src, dst):
                    try:
                        while True:
                            data = src.recv(BUFFER_SIZE)
                            if not data:
                                break
                            dst.sendall(data)
                    finally:
                        src.close()
                        dst.close()

                threading.Thread(target=forward, args=(client_socket, target)).start()
                threading.Thread(target=forward, args=(target, client_socket)).start()

            except Exception as e:
                print(f"[!] Gagal konek ke SSH: {e}")
                client_socket.close()
        else:
            client_socket.send(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            client_socket.close()

    except Exception as e:
        print(f"[!] Error: {e}")
        client_socket.close()

def start():
    os.system("fuser -k 80/tcp")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((LISTEN_HOST, LISTEN_PORT))
    sock.listen(100)
    print(f"[+] Listening on {LISTEN_HOST}:{LISTEN_PORT}...")

    while True:
        client, addr = sock.accept()
        print(f"[+] Koneksi dari {addr[0]}:{addr[1]}")
        threading.Thread(target=handle, args=(client,)).start()

if __name__ == "__main__":
    start()
EOF

chmod +x /etc/sshws/ws-server.py

# 4. Buat systemd service
cat << EOF > /etc/systemd/system/sshws.service
[Unit]
Description=SSH over WebSocket Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /etc/sshws/ws-server.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 5. Reload dan aktifkan service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sshws
systemctl restart sshws

# 6. Output sukses
echo "✅ SSH WebSocket server berhasil diinstall dan dijalankan di port 80."
echo "Gunakan payload seperti:"
echo ""
echo "GET / HTTP/1.1[crlf]"
echo "Host: $(curl -s ifconfig.me)[crlf]"
echo "Upgrade: websocket[crlf]"
echo "Connection: Upgrade[crlf][crlf]"
