#!/bin/sh

# initialize cluster
k3d cluster create p3

# create dev and argocd namespaces
kubectl apply -f /vagrant/confs/namespaces.yaml

# set argocd namespace as default
kubectl config set-context --current --namespace=argocd

# install argocd in argocd namespace
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# forward port and get pid of the forwarder
kubectl port-forward svc/argocd-server 8080:443 &
port_forward_pid=$!

# add the app
argocd app create wilapp --repo https://github.com/achansel/anggonza-iot-p3.git --dest-server https://kubernetes.default.svc --dest-namespace dev

# sync it
argocd app sync wilapp

# kill the forwarder
kill $port_forward_pid
