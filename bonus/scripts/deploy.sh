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

# clone the new GitLab repo
echo "CLONING GITLAB REPO..."
GITLAB_REPO="https://gitlab.achansel.com/root/$PROJECT_NAME.git"
# config for one time avoid ssl verification
git config --global http.sslVerify false
# it asks for the password, so we need to set it
echo "https://root:$GITLAB_PASSWORD@gitlab.achansel.com" > ~/.git-credentials
git config --global credential.helper store
git clone $GITLAB_REPO
git config --global user.email "achansel@42.fr"
git config --global user.name "achansel"
# copy the app to the new repo
echo "COPYING APP TO GITLAB REPO..."
GITHUB_REPO="https://github.com/achansel/anggonza-iot-p3.git"
git clone $GITHUB_REPO to_copy
cp -r to_copy/* $PROJECT_NAME/
rm -rf to_copy
cd $PROJECT_NAME
git add .
git commit -m "Initial commit"
git push
git config --global http.sslVerify true
cd ..
rm -rf anggonza-iot-p3
git config --global --unset user.email  
git config --global --unset user.name
rm -rf ~/.git-credentials
git config --global --unset credential.helper


openssl s_client -showcerts -servername gitlab.achansel.com -connect $GITLAB_IP:443 </dev/null 2>/dev/null | openssl x509 -outform PEM > gitlab.crt
argocd cert add-tls gitlab.achansel.com --from gitlab.crt
# echo "GETTING CA CERT..."
# kubectl get secret gitlab-gitlab-tls -n gitlab -o jsonpath='{.data.tls\.key}' | base64 --decode > gitlab-ca.crt

# add the app, gitlab auto sync will be done every 3 minutes (default config)
argocd login --core
argocd app create wilapp --repo $GITLAB_REPO --path . --dest-server https://kubernetes.default.svc --dest-namespace dev --sync-policy automated --auto-prune --insecure

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
