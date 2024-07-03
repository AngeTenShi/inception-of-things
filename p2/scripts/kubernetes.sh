
echo "Installing k3s"
curl -sfL https://get.k3s.io | sh -s - 

echo "Applying kubernetes resources"
kubectl apply -f /home/vagrant/confs/app1.yaml
kubectl apply -f /home/vagrant/confs/app2.yaml
kubectl apply -f /home/vagrant/confs/app3.yaml
kubectl apply -f /home/vagrant/confs/ingress.yaml
