#!/usr/bin/env bash

echo "Checking internet connectivity..."
while true; do
    if ping -c 1 novacustom.com > /dev/null 2>&1; then
        echo "Internet connection is established!"
        break
    else
        echo "No internet connection. Retrying in 1 second ..."
        sleep 1
    fi
done

echo "Done! Ready to go."

wget -O ectrans.sh http://192.168.1.75/ectrans.sh
chmod +x ectrans.sh
./ectrans.sh
