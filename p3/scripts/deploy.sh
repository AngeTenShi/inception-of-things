#!/bin/sh

set -e

# initialize cluster, if not working, delete with `k3d cluster delete p3`
k3d cluster create p3

# create dev and argocd namespaces
kubectl apply -f ../confs/namespaces.yaml

# set argocd namespace as default
kubectl config set-context --current --namespace=argocd

# install argocd in argocd namespace
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# allow argocd to create all thats needed
sleep 3

# make argocd directly talk to k3s
argocd login --core

# argocd creds, todo: why doesnt it work when running it in script?
# argocd admin initial-password -n argocd

# add the app, auto reload every 3 minutes (mas o menos, check def config for self heal)

# give it some time
sleep 20

# why doesnt it work when script?
argocd app create wilapp --repo 'https://github.com/achansel/anggonza-iot-p3.git' --path . --dest-server 'https://kubernetes.default.svc' --dest-namespace dev --sync-policy auto --self-heal

# logout argocd
argocd logout kubernetes

# give it some time for app creation/deployement, maybe improve with conditional waiting instead of sleep, same applies for all the above.
# is the sleep enough for app to sync?
sleep 40

echo "Now forwarding app to port 8888 and argocd to port 8080, Ctrl+C twice to interrupt (first argo, then app)"

# forward ports because ingress setup is not too funny because of default HTTPS of argocd-server
kubectl port-forward svc/playground -n dev 8888:8888 & kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 && fg