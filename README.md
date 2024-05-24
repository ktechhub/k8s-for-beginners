# 1. Installation 
Prerequisites
```sh
Docker
Kubectl
```

1. Linux
```sh
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64
chmod +x ./kind
mv ./kind /some-dir-in-your-PATH/kind   # mv ./kind /usr/bin #ubuntu move /usr/local/bin
```

2. macOS
```sh
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-darwin-amd64
chmod +x ./kind
mv ./kind /some-dir-in-your-PATH/kind
```

3. PowerShell
```sh
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.11.1/kind-windows-amd64
Move-Item .\kind-windows-amd64.exe c:\some-dir-in-your-PATH\kind.exe
```

# 2. Verify installation
```sh
# See version of kind
kind version

# See other arguments for kind
kind --help
```

# 3. Create a cluster
```
You can create a single-node cluster or a multi-node cluster
```
## 3a. For single-node cluster:
```sh
kind create cluster --name <cluster-name>       # defaults to "kind" if name is not provided

kind create cluster --name tiacloud             # we'll be using tiacloud for this setup
```

## 3b. For a multi-node cluster, use a config file to add extra nodes
```yml
# A sample multi-node cluster config file
# A three node (two workers, one controller) cluster config
# To add more worker nodes, add another role: worker to the list
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: tiacloud
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"    
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
```
```sh
# Then run the cluster config file
kind create cluster --config <cluster-config-yaml>
```

### Note: omit the `<>` when subtituting with values

```sh
# Automatically the context will be set. However, you can still set it yourself with:
kind export kubeconfig --name tiacloud
kubectl config view                       # To view the context
```

# 4. Deploy Nginx controller
```sh
# Deploy an nginx-ingress controller. To be used later with an ingress resource
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

# Deploy a sample app
```yml
kind: Pod                                      # For testing purposes. Don't run only a pod object in production
apiVersion: v1
metadata:
  name: tiacloud-app
  labels:
    app: tiacloud-app
spec:
  containers:
  - name: tiacloud-app
    image: hashicorp/http-echo:0.2.3           # We'll later replace this image with a built image
    args:
    - "-text=Hello World! This is a daba Kubernetes with kind App"
---
kind: Service
apiVersion: v1
metadata:
  name: daba-service
spec:
  selector:
    app: tiacloud-app
  ports:
  - port: 5678
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: daba-ingress
spec:
  rules:
  - http:
      paths:
      - pathType: Prefix
        path: "/tiacloud"
        backend:
          service:
            name: daba-service
            port:
              number: 5678
---
```
```sh
# Apply
kubectl apply -f sample-app/app.yml
```

# 5. Check Deployments
```sh
kubectl get services
kubectl get pods
```

- Navigate to the browser and check `localhost/tiacloud` to see the app running

# 6. Build Your own Local Image
```sh
docker build -t ttw:0.1.0 .
kind load docker-image ttw:0.1.0 --name tiacloud
docker exec -it my-node-name crictl images                         # Check all images in controller node

# Use the local image in your manifest yaml and deploy
# Refer to updated manifest in sample-app/local_image_app.yml

# Then Deploy
kubectl apply -f sample-app/local_image_app.yml

# Go to localhost on localhost/ttw, OR

# Port-forward pod to localhost
kubectl port-forward pods/tiacloud-app-2 :3000                    # Make sure port in Dockerfile matches the targetPort
```

# 7. Metallb Setup
- To use a LoadBalancer you will have to use Metallb controller. You can extend this with a domain name as we will demostrate

```sh
# create metallb namespace
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml

# Apply metallb manifest
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml


# Setup address pool used by loadbalancers
# To complete layer2 configuration, we need to provide metallb a range of IP addresses it controls. We want this range to be on the docker kind network.

docker network inspect -f '{{.IPAM.Config}}' kind

# The output will contain a cidr such as 172.19.0.0/16. We want our loadbalancer IP range to come from this subclass. We can configure metallb, for instance, to use 172.19.255.200 to 172.19.255.250 by creating the configmap.

```
```yml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 172.19.255.200-172.19.255.250
```
```sh
# Deploy the address-pool range for the loadbalancer
kubectl apply -f metallb/lb-address-pool.yml -n metallb-system

# Redeploy your service with type LoadBalancer
```
```yml
kind: Service
apiVersion: v1
metadata:
  name: tiacloud-service-1
spec:
  type: LoadBalancer
  selector:
    app: tiacloud-app-1
  ports:
  - port: 5678
```
```sh
# Fetch the IP of the service
LB_IP=$(kubectl get svc/tiacloud-service -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $LB_IP

# Curl the LoadBalancer headers
curl -I $LB_IP

# Also check it out in the browser
```

# 8. Use IP with Domain
```sh
# Edit your /etc/hosts with the domain
172.19.255.20     example.link.com

# Go the browser on
http://example.link.com
```

# 9. Clean Up
```sh
kind get clusters                                 # Get you clusters (choose which to delete
kind cluster-info --context tiacloud              # get cluster info with the a context
kind delete cluster --name tiacloud               # Default delete is kind
```

# 10. Troubleshooting

## ** Service problem
1. If you encouter any error after deploying the `app.yml` related to the `validate.nginx.ingress.kubernetes.io webhook`, delete the `ValidationWebhookConfiguration`

```sh
kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission
```

2. Then redeploy the service again, i.e `app.yml` in `sample-app/app.yml`

## ** Port 80 problem
1. If you are unable to create the cluster with the `cluster_config.yml` due to port 80 being in use. Check and kill the process running on it

```sh
sudo lsof -i -P -n | grep 80        # apached is using port 80
ps aux | grep -i apache2            # grab its pids
sudo kill -9 pid                    # kill 1 pid
killall apache2                     # kill all pids
```

3. Several pods do not start, encounter "too many open files" error #2087
```sh
# (10x previous values) solved this problem on k0s instance
sudo sysctl fs.inotify.max_user_instances=1280
sudo sysctl fs.inotify.max_user_watches=655360
```
