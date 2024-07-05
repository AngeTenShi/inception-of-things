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

# TODO: Make it work, pods have to be created in order to be able to wait for them after, that's what needs to be awaited, the interface is really bad
set +e
while true; do
	kubectl get pods
	if [ "$?" = "0" ]; then
		break
	fi
done
set -e

kubectl wait --for=condition=ready pods --all --namespace=argocd --timeout=600s

#TODO: After
# get creds (https://stackoverflow.com/questions/68297354/what-is-the-default-password-of-argocd)
echo "GETTING ARGOCD CREDS..."
echo "argocd creds: (user: admin, password is: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d))"

# give it some time
sleep 20

# add the app, auto reload every 3 minutes (mas o menos, check def config for self heal)
kubectl apply -f ../confs/wilapp-manifest.yaml

# probably same here, as the todo above
kubectl wait --for=condition=available deployment playground --namespace=dev --timeout=600s

# give it some time for app creation/deployement, maybe improve with conditional waiting instead of sleep, same applies for all the above.
# is the sleep enough for app to sync?
sleep 40

echo "Now forwarding app to port 8888 and argocd to port 8080, Ctrl+C twice to interrupt (first argo, then app)"

# forward ports because ingress setup is not too funny because of default HTTPS of argocd-server
kubectl port-forward svc/playground -n dev 8888:8888 & kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 && fg