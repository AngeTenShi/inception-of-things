#!/bin/sh

CURRENT_PATH=$(pwd)
#Checking if cluster exits
if k3d cluster get p3 2>/dev/null; then
  k3d cluster delete p3
fi

# initialize cluster, if not working, delete with `k3d cluster delete p3`
echo "CREATING CLUSTER..."
k3d cluster create --k3s-arg "--disable=traefik@server:*" p3

# create namspaces and set argocd as default
echo "CREATING NAMESPACES..."
kubectl apply -f $CURRENT_PATH/../confs/namespaces.yaml
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


kubectl apply -f $CURRENT_PATH/../confs/helm-gitlab.yaml 
# 7 min to launch almost
set +e
while true; do
  if kubectl wait --for=condition=available deployment gitlab-webservice-default --namespace=gitlab --timeout=600s 2>/dev/null; then
    break
  fi
done
set -e


# CREATE THE REPO
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -ojsonpath='{.data.password}' | base64 --decode ; echo)
GITLAB_IP=$(kubectl get svc gitlab-nginx-ingress-controller -n gitlab -ojsonpath='{.status.loadBalancer.ingress[0].ip}')

# remove insecure when not self-signed no more
alias curl='curl --insecure --header "Host: gitlab.example.com"'

GITLAB_TOKEN=$(curl --header "Content-Type: application/json" -X POST "https://$GITLAB_IP/oauth/token?grant_type=password&username=root&password=$GITLAB_PASSWORD" --insecure | jq -r '.access_token')

PROJECT_NAME="anggonza-iot-p3"
curl -v --header "Authorization: Bearer $GITLAB_TOKEN" -X POST "https://$GITLAB_IP/api/v4/projects" --data "name=$PROJECT_NAME"

sleep 10

# Import GitHub repo to GitLab
GITHUB_REPO="https://github.com/achansel/anggonza-iot-p3.git"
echo "IMPORTING GITHUB REPO TO GITLAB..."
# TODO: FIX THIS: https://docs.gitlab.com/ee/api/import.html#import-repository-from-github --> maybe clone it then push?
curl --header "Authorization: Bearer $GITLAB_TOKEN" -X POST "https://$GITLAB_IP/api/v4/projects/$PROJECT_NAME/import" --data "url=$GITHUB_REPO"

# todo: add right host here, so that it forwards to the right host, also fix the certificate.
GITLAB_REPO="https://$GITLAB_IP/$PROJECT_NAME.git"

# add the app, gitlab auto sync will be done every 3 minutes (default config)
argocd app create wilapp --repo $GITLAB_REPO --path . --dest-server 'https://kubernetes.default.svc' --dest-namespace dev --sync-policy auto --self-heal

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
