#!/bin/bash
sudo apt update
sudo apt install -y wget gnupg
sudo mkdir -p /etc/apt/keyrings
wget -O- https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /etc/apt/keyrings/adoptium.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb stable main" | sudo tee /etc/apt/sources.list.d/adoptium.list
sudo apt update
sudo apt install -y openjdk-21-jdk
##sudo apt install -y temurin-21-jdk
java -version
