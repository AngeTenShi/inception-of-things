#!/bin/sh

CURRENT_PATH=$(pwd)
#Checking if cluster exits
if k3d cluster get p3 2>/dev/null; then
  k3d cluster delete p3
fi

# initialize cluster, if not working, delete with `k3d cluster delete p3`
echo "CREATING CLUSTER..."
k3d cluster create p3

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

helm repo add gitlab https://charts.gitlab.io 2>/dev/null
helm repo update
helm install gitlab gitlab/gitlab -f $CURRENT_PATH/../confs/values.yaml --namespace gitlab


# kubectl apply -f $CURRENT_PATH/../confs/gitlab-project.yaml it seems that it's not needed
kubectl apply -f $CURRENT_PATH/../confs/helm-gitlab.yaml 
# 7 min to launch almost
kubectl wait --for=condition=available deployment gitlab-webservice-default --namespace=gitlab --timeout=600s

# CREATE THE REPO
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -ojsonpath='{.data.password}' | base64 --decode ; echo)
GITLAB_IP=$(kubectl get svc gitlab-webservice-default -n gitlab -ojsonpath='{.spec.clusterIP}')
PERSONAL_ACCESS_TOKEN=$(curl --header "Content-Type: application/json" --request POST "http://$GITLAB_IP/api/v4/session?login=root&password=$GITLAB_PASSWORD" | jq -r '.private_token')
PROJECT_NAME="anggonza-iot-p3"
curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -X POST "$GITLAB_URL/api/v4/projects" --data "name=$PROJECT_NAME"
sleep 60

# Import GitHub repo to GitLab
GITHUB_REPO="https://github.com/achansel/anggonza-iot-p3.git"
echo "IMPORTING GITHUB REPO TO GITLAB..."
curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -X POST "$GITLAB_URL/api/v4/projects/$PROJECT_NAME/import" --data "url=$GITHUB_REPO"


GITLAB_REPO="$GITLAB_URL/$PROJECT_NAME.git"
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
