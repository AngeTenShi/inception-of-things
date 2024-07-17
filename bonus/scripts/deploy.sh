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
alias curl='curl --insecure --header "Host: gitlab.achansel.com"'

GITLAB_TOKEN=$(curl "Content-Type: application/json" -X POST "https://$GITLAB_IP/oauth/token?grant_type=password&username=root&password=$GITLAB_PASSWORD" | jq -r '.access_token')

PROJECT_NAME="anggonza-iot-p3"
curl --request POST \
  --url "https://$GITLAB_IP/api/v4/projects" \
  --header "content-type: application/json" \
  --header "Authorization: Bearer $GITLAB_TOKEN" \
  --data '{
    "name": "'"$PROJECT_NAME"'",
    "visibility": "public"
  }'

echo "$GITLAB_IP gitlab.achansel.com" | sudo tee -a /etc/hosts

GITLAB_REPO="https://gitlab.achansel.com/root/anggonza-iot-p3.git"
GITHUB_REPO="https://github.com/achansel/anggonza-iot-p3.git"
git clone $GITHUB_REPO to_copy
cd to_copy
git config --global http.sslVerify false
git config --global user.email "achansel@42.fr"
git config --global user.name "achansel"
echo "https://root:$GITLAB_PASSWORD@gitlab.achansel.com" > ~/.git-credentials
git config --global credential.helper store
git push $GITLAB_REPO master
git config --global --unset credential.helper
cd .. 
rm -rf to_copy
rm -rf ~/.git-credentials

# add the app, gitlab auto sync will be done every 3 minutes (default config)
argocd login --core
GITLAB_WS_POD=$(kubectl get svc -n gitlab gitlab-webservice-default -ojsonpath='{.spec.clusterIP}')
argocd app create wilapp --repo http://$GITLAB_WS_POD/root/anggonza-iot-p3.git --path . --dest-server https://kubernetes.default.svc --dest-namespace dev --sync-policy automated --auto-prune

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
