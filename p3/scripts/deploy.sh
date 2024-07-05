#!/bin/sh

set -e

# initialize cluster, if not working, delete with `k3d cluster delete p3`
echo "CREATING CLUSTER..."
k3d cluster create p3

# create namspaces and set argocd as default
echo "CREATING NAMESPACES..."
kubectl apply -f ../confs/namespaces.yaml
kubectl config set-context --current --namespace=argocd

# install argocd in argocd namespace
echo "INSTALLING ARGOCD..."
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# loop because they cannot be awaited at first since they are not even created.
set +e
while true; do
  if kubectl wait --for=condition=ready pods --all --timeout=600s 2>/dev/null; then
    break
  fi
done
set -e

# get creds (https://stackoverflow.com/questions/68297354/what-is-the-default-password-of-argocd)
echo "GETTING ARGOCD CREDS..."
echo "argocd creds: (user: admin, password is: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d))"

# add the app, github auto sync will be done every 3 minutes (default config)
argocd app create wilapp --repo 'https://github.com/achansel/anggonza-iot-p3.git' --path . --dest-server 'https://kubernetes.default.svc' --dest-namespace dev --sync-policy auto --self-heal

# same as the previous similar loop
set +e
while true; do
  if kubectl wait --for=condition=available deployment playground --namespace=dev --timeout=600s 2>/dev/null; then
    break
  fi
done
set -e


echo "Now forwarding app to port 8888 and argocd to port 8080, Ctrl+C twice to interrupt (first argo, then app)"

# forward ports because ingress setup is not too funny because of default HTTPS of argocd-server
kubectl port-forward svc/playground -n dev 8888:8888 & kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 && fg
