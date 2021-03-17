# Get AKS credentials
az aks get-credentials --resource-group fnopa-qa-spoke-rg --name fnopa-qa-aks

# Create a namespace for your ingress resources
kubectl create namespace ingress-nginx

# Add the ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Install ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.nodeSelector."beta\.kubernetes\.io/os"=linux \
    -f ingress/internal-ingress.yaml

# Generate self-signed certificate for TLS
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout tls_cert.key -out tls_cert.crt -subj "/C=DE/ST=NRW/O=IT, Netcamp Ltd./CN=app20.netcamp.eu"

kubectl create secret tls tls-secret --key tls_cert.key --cert tls_cert.crt