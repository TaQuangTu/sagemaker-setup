#!/usr/bin/env bash

set -e

NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz"
NGROK_DIR="/home/ec2-user/SageMaker/.ngrok"
NGROK_LOG="/var/log/ngrok.log"
SSH_DIR="/home/ec2-user/SageMaker/ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
SSH_INSTRUCTIONS="/home/ec2-user/SageMaker/SSH_INSTRUCTIONS"

echo "Setting up SSH with ngrok..."

echo "Downloading ngrok..."
curl -sSL "$NGROK_URL" -o ngrok.tgz
tar -xzf ngrok.tgz

echo "Creating ngrok config file..."
mkdir -p "$NGROK_DIR"
cat > "$NGROK_DIR/config.yml" << EOF
authtoken: $NGROK_AUTH_TOKEN
tunnels:
  ssh:
    proto: tcp
    addr: 22
version: 2
EOF
chown -R ec2-user:ec2-user "$NGROK_DIR"

echo "Creating start-ngrok-ssh script..."
cat > /usr/bin/start-ngrok-ssh << 'EOF'
#!/usr/bin/env bash

set -e

NGROK_LOG="/var/log/ngrok.log"
SSH_INSTRUCTIONS="/home/ec2-user/SageMaker/SSH_INSTRUCTIONS"
NGROK_DIR="/home/ec2-user/SageMaker/.ngrok"

echo "Starting ngrok..."
sudo touch "$NGROK_LOG"
sudo chown ec2-user:ec2-user "$NGROK_LOG"
sudo chmod 664 "$NGROK_LOG"
sudo ./ngrok start --all --log=stdout --config "$NGROK_DIR/config.yml" > "$NGROK_LOG" &
sleep 10

TUNNEL_URL=$(grep -Eo 'url=https://.*' "$NGROK_LOG" | cut -d= -f2)
if [[ -z "$TUNNEL_URL" ]]; then
    echo "Failed to set up SSH with ngrok"
    echo "ngrok logs:"
    cat "$NGROK_LOG"
    exit 1
fi

echo "SSH address: $TUNNEL_URL"
sudo touch "$SSH_INSTRUCTIONS"
sudo chown ec2-user:ec2-user "$SSH_INSTRUCTIONS"
sudo chmod 664 "$SSH_INSTRUCTIONS"
cat > "$SSH_INSTRUCTIONS" << EOD
SSH enabled through ngrok!
Address: $TUNNEL_URL

Use 'ssh -p <port_from_above> ec2-user@<host_from_above>' to SSH here!
EOD
EOF
chmod +x /usr/bin/start-ngrok-ssh
chown ec2-user:ec2-user /usr/bin/start-ngrok-ssh

echo "Creating copy-ssh-keys script..."
mkdir -p "$SSH_DIR" && chown -R ec2-user:ec2-user "$SSH_DIR"
cat > /usr/bin/copy-ssh-keys << 'EOF'
#!/usr/bin/env bash

set -e

SSH_DIR="/home/ec2-user/SageMaker/ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

touch "$AUTH_KEYS"
chown ec2-user:ec2-user "$AUTH_KEYS"

cnt=$(wc -l < "$AUTH_KEYS")
echo "Copying $cnt SSH keys..."
cp "$AUTH_KEYS" /home/ec2-user/.ssh/authorized_keys
EOF
chmod +x /usr/bin/copy-ssh-keys
chown ec2-user:ec2-user /usr/bin/copy-ssh-keys

echo "Copying SSH keys..."
copy-ssh-keys

echo "Starting ngrok SSH..."
start-ngrok-ssh

echo "Setup complete."
