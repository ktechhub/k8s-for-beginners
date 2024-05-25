# 1. Installation 
Prerequisites
```sh
Docker
Kubectl
```

## 1a. Installing with a Package Manager
```sh
# On MacOS via Homebrew
brew install kind

# On MacOS via MacPorts
sudo port selfupdate && sudo port install kind

# On Windows via Chocolatey
choco install kind
```

## 1b. Installing From Release Binaries 🔗︎
1. On Linux
```sh
# For AMD64 / x86_64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
# For ARM64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-arm64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

2. On macOS
```sh
# For Intel Macs
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-darwin-amd64
# For M1 / ARM Macs
[ $(uname -m) = arm64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-darwin-arm64
chmod +x ./kind
mv ./kind /some-dir-in-your-PATH/kind
```

3. On Windows in PowerShell
```sh
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.23.0/kind-windows-amd64
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

kind create cluster --name storm             # we'll be using storm for this setup
```

## 3b. For a multi-node cluster, use a config file to add extra nodes
```yml
# A sample multi-node cluster config file
# A three node (two workers, one controller) cluster config
# To add more worker nodes, add another role: worker to the list
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: storm
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
```
```sh
# Then run the cluster config file
kind create cluster --config <cluster-config-yaml>
```

### Note: omit the `<>` when subtituting with values

```sh
# Automatically the context will be set. However, you can still set it yourself with:
kind export kubeconfig --name storm
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
  name: storm-app
  labels:
    app: storm-app
spec:
  containers:
  - name: storm-app
    image: hashicorp/http-echo:0.2.3           # We'll later replace this image with a built image
    args:
    - "-text=Hello World! This is a storm Kubernetes with kind App"
---
kind: Service
apiVersion: v1
metadata:
  name: storm-service
spec:
  selector:
    app: storm-app
  ports:
  - port: 5678
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

- Navigate to the browser and check `localhost/storm` to see the app running
```sh
kubectl port-forward po/
```

# 6. Build Your own Local Image
```sh
docker build -t storm-image:0.0.1 .
kind load docker-image storm-image:0.0.1 --name storm
docker exec -it my-node-name crictl images                         # Check all images in controller node

# Use the local image in your manifest yaml and deploy
# Refer to updated manifest in sample-app/local_image_app.yml

# Then Deploy
kubectl apply -f sample-app/local_image_app.yml

# Go to localhost on localhost/ttw, OR

# Port-forward pod to localhost
kubectl port-forward pods/storm-app-2 :3000                    # Make sure port in Dockerfile matches the targetPort
```

# ADVANCED!!!
# 7a. Load Balancing using Kind Cloud Provider Utility

# 7. Metallb Setup (Deprecated)
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
      - 172.18.255.200-172.18.255.250
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
  name: storm-service-1
spec:
  type: LoadBalancer
  selector:
    app: storm-app-1
  ports:
  - port: 5678
```
```sh
# Fetch the IP of the service
LB_IP=$(kubectl get svc/storm-service-1 -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
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
kind cluster-info --context storm              # get cluster info with the a context
kind delete cluster --name storm               # Default delete is kind
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
