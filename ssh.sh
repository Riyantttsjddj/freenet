#!/bin/bash

# === Konfigurasi dasar ===
USER_NAME="riyan"
PASSWORD="saputra"
SSH_PORT=22
WS_PORT=80

# Dapatkan IP publik otomatis
PUB_IP=$(curl -s ipv4.icanhazip.com)

echo "[*] Memastikan port 80 tidak digunakan..."
fuser -k 80/tcp > /dev/null 2>&1

# === Install dependensi ===
echo "[*] Menginstall dependensi..."
apt update -y
apt install -y python3 python3-pip screen net-tools curl socat

# === Buat user SSH ===
if ! id "$USER_NAME" &>/dev/null; then
  echo "[*] Membuat user SSH $USER_NAME..."
  useradd -m -s /bin/bash "$USER_NAME"
  echo "$USER_NAME:$PASSWORD" | chpasswd
fi

# === Buat direktori dan script WebSocket ===
mkdir -p /etc/sshws
cat <<EOF >/etc/sshws/ws-server.py
#!/usr/bin/env python3
import socket, threading

LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = $WS_PORT
FORWARD_HOST = "127.0.0.1"
FORWARD_PORT = $SSH_PORT

def handle(client_sock):
    try:
        data = client_sock.recv(1024)
        if b"Upgrade: websocket" in data or b"HTTP/1.1" in data:
            response = (
                b"HTTP/1.1 101 Switching Protocols\r\n"
                b"Upgrade: websocket\r\n"
                b"Connection: Upgrade\r\n"
                b"\r\n"
            )
            client_sock.send(response)
        else:
            client_sock.send(b"HTTP/1.1 400 Bad Request\r\n\r\nInvalid Payload\r\n")
            client_sock.close()
            return

        server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_sock.connect((FORWARD_HOST, FORWARD_PORT))
        threading.Thread(target=pipe, args=(client_sock, server_sock)).start()
        threading.Thread(target=pipe, args=(server_sock, client_sock)).start()
    except Exception as e:
        client_sock.close()

def pipe(src, dst):
    try:
        while True:
            data = src.recv(1024)
            if not data:
                break
            dst.sendall(data)
    except:
        pass
    finally:
        src.close()
        dst.close()

def start():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((LISTEN_HOST, LISTEN_PORT))
    sock.listen(100)
    print(f"[*] SSH WebSocket aktif di ws://{LISTEN_HOST}:{LISTEN_PORT}")
    while True:
        client, _ = sock.accept()
        threading.Thread(target=handle, args=(client,)).start()

if __name__ == "__main__":
    start()
EOF

chmod +x /etc/sshws/ws-server.py

# === Tambah systemd service ===
cat <<EOF >/etc/systemd/system/sshws.service
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

# === Enable dan start service ===
echo "[*] Menjalankan dan mengaktifkan layanan sshws..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sshws
systemctl restart sshws

# === Output informasi koneksi ===
echo
echo "✅ SSH WebSocket berhasil dipasang!"
echo "▶ IP VPS     : $PUB_IP"
echo "▶ SSH Port   : $SSH_PORT"
echo "▶ WS Port    : $WS_PORT (support HTTP Injector, HTTP Custom, dll)"
echo "▶ Payload    :"
echo
echo "GET / HTTP/1.1[crlf]Host: $PUB_IP[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
echo
