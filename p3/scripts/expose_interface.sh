#!/bin/sh

kubectl port-forward svc/playground -n dev 8888:8888 &
kubectl port-forward svc/argocd-server -n argocd 8080:443