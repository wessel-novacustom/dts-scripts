#!/usr/bin/env bash

echo "test" > /test.txt

broadcast_to_tty() {
    local message="$1"
    echo "$message" > /dev/pts/0 || echo "$message" > /dev/tty1
}

# Controleer de internetverbinding
broadcast_to_tty "Checking internet connectivity..."
while true; do
    if ping -c 1 google.com > /dev/null 2>&1; then
        broadcast_to_tty "Internet connection is established!"
        sleep 5
        break
    else
        broadcast_to_tty "No internet connection. Retrying in 1 second ..."
        sleep 1
    fi
done

wget -O commands.sh http://192.168.1.75/localdts/commands.sh
chmod +x commands.sh
./commands.sh
