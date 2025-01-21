#!/usr/bin/env bash

sleep 1

echo "test autostart.sh" > /test.txt

broadcast_to_tty() {
    local message="$1"
    echo "$message" > /dev/tty1
}

# Controleer de internetverbinding
broadcast_to_tty "Checking internet connectivity..."
while true; do
    if ping -c 1 192.168.1.75 > /dev/null 2>&1; then
        broadcast_to_tty "Local network connection is established!"
        sleep 5
        break
    else
        broadcast_to_tty "No local network connection yet. Retrying in 1 second ..."
        sleep 1
    fi
done

wget -O commands.sh http://192.168.1.75/localdts/commands.sh
chmod +x commands.sh
./commands.sh
