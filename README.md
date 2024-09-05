# HOW TO INSTALL

## KUBERNETES

For example, using **minikube**:

`minikube start`

`minikube addons enable ingress`

`minikube tunnel` (if using WSL or similar)

## ARGO CD

`kubectl apply -f https://github.com/Daglesia/domain-infra/tree/master/argocd`

Yeah. That's kinda it.