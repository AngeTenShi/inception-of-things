#!/bin/sh

set -e

# FOR debian12
sudo apt update

# cURL
sudo apt install -y curl

# docker
sudo apt install -y docker.io
sudo adduser $USER docker

# k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# argocd
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 755 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

echo "success"