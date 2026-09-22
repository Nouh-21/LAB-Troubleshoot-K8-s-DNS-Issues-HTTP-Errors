#!/bin/bash

clear
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}=========================================================${NC}"
echo -e "   🚀 WEZVATECH ULTIMATE K8s HTTP HANDSHAKE WORKSHOP     "
echo -e "${CYAN}=========================================================${NC}"


# -- Create Kind Cluster -- #
kind create cluster --config kind_config.yaml --name wezvatech-lab
echo -e "\n${GREEN}▶ Test Kubernetes Cluster Created ..."

# --- SCENARIO 1: 200 OK ---
echo -e "\n${GREEN}▶ SCENARIO 1: The Healthy Baseline (200 OK)${NC} \n"
kubectl apply -f 1-healthy-200.yaml
echo -e "\n \n"
read -p " Press [Enter] to proceed to the next scenario..."
clear

# --- SCENARIO 2: 301 REDIRECT ---
echo -e "\n${GREEN}▶ SCENARIO 2: Protocol Redirection (301 Moved Permanently)${NC}"
kubectl apply -f 2-redirect-301.yaml

echo -e "\n${YELLOW}💡 TROUBLESHOOTING STEPS:${NC}"
echo -e "\nStep 1: Track the Redirect Path (The Terminal Proof) \n curl -ivL http://localhost"
echo -e "\nStep 2: Checking Ingress Layer 301s (SSL and Global Rules) \n kubectl get ingress <ingress-name> -o yaml"
echo -e "\nStep 3: Checking Application Pod Layer 301s (Trailing Slashes) \n kubectl logs -f <PODNAME>  \n"
read -p " Press [Enter] to proceed to the next scenario..."
clear

# --- SCENARIO 3: 401 UNAUTHORIZED ---
echo -e "\n${GREEN}▶ SCENARIO 3: Identity Authorization Deficiencies (401 Unauthorized)${NC}"
kubectl apply -f 3-client-401.yaml

echo -e "\n${YELLOW}💡 TROUBLESHOOTING STEPS:${NC}"
echo -e "\nStep 1: Identify Where the 401 is Triggered \n curl -v http://localhost"
echo -e "\nStep 2: Debugging Ingress / External Auth 401 \n kubectl get ingress <ingress-name> -o yaml"
echo -e "\nStep 3: Debugging Application Pod 401 (Token & Env Variables) \n kubectl logs -f <PODNAME>  \n"
read -p " Press [Enter] to proceed to the next scenario..."
clear

# --- NEW SCENARIO 4: 404 NOT FOUND ---
echo -e "\n${GREEN}▶ SCENARIO 4: Missing Endpoints / Assets (404 Not Found)${NC}"
kubectl apply -f 4-client-404.yaml

echo -e "\n${YELLOW}💡 TROUBLESHOOTING STEPS:${NC}"
echo -e "\nStep 1: Identify Who Threw the 404 (Ingress vs. Application) \n curl -v http://localhost"
echo -e "\nStep 2: Debugging an Ingress 404 (Path Mismatch) \n kubectl get ingress <ingress-name> -o yaml"
echo -e "\nStep 3: Debugging an Application 404 (Code or Data Issue) \n kubectl logs -f <PODNAME>  \n"
read -p " Press [Enter] to proceed to the next scenario..."
clear

# --- NEW SCENARIO 5: 500 INTERNAL SERVER ERROR ---
echo -e "\n${GREEN}▶ SCENARIO 5: Application Exceptions (500 Internal Server Error)${NC}"
kubectl apply -f 5-server-500.yaml

echo -e "\n${YELLOW}💡 TROUBLESHOOTING STEPS:${NC}"
echo -e "\nStep 1: Dump the Live Application Logs \n kubectl logs -f <PODNAME>"
echo -e "\nStep 2: Check External Service and Database Connectivity \n kubectl exec -it <pod-name> -- nc -zv <db-service-name> <db-port>"
echo -e "\nStep 3: Verify Missing Environment Variables or Secrets \n kubectl exec -it <pod-name> -- env"
echo -e "\nStep 4: Rule out Permissions and File System Blocks \n check for 'readOnlyRootFilesystem: true' in your yaml  \n"
read -p " Press [Enter] to proceed to the next scenario..."
clear

# --- SCENARIO 6: 502 BAD GATEWAY ---
echo -e "\n${GREEN}▶ SCENARIO 6: Immediate Runtime Crashes (502 Bad Gateway)${NC}"
kubectl apply -f 6-badgateway-502.yaml

echo -e "\n${YELLOW}💡 TROUBLESHOOTING STEPS:${NC}"
echo -e "\nStep 1: The Application Crashed Mid-Request (OOMKilled) \n kubectl get pods"
echo -e "\nStep 2: Node/Process Layer Misconfiguration \n kubectl logs -f <PODNAME>"
echo -e "\nStep 3: Protocol Mismatch (HTTP vs. HTTPS) \n kubectl get ingress <ingress-name> -o yaml  \n"
read -p " Press [Enter] to proceed to the next scenario..."
clear

# --- SCENARIO 7: 503 SERVICE UNAVAILABLE ---
echo -e "\n${GREEN}▶ SCENARIO 7: Infrastructure Orchestration Dropouts (503 Service Unavailable)${NC}"
kubectl apply -f 7-serviceunavailable-503.yaml
kubectl patch service wezva-service -p '{"spec":{"selector":{"app":"fallback-handler"}}}'


echo -e "\n${YELLOW}💡 TROUBLESHOOTING STEPS:${NC}"
echo -e "\nStep 1: Check the Pod Status \n kubectl get pods"
echo -e "\nStep 2: Inspect Pod Readiness Probes \n kubectl describe pod <PODNAME>"
echo -e "\nStep 3: Verify the Kubernetes Service & Endpoints \n kubectl get endpoints wezva-service"
echo -e "\nStep 4: Inspect the Ingress Controller Logs (Traefik or Istio) \n kubectl logs -n <ingress-namespace> <ingress-pod-name> \n"
read -p "  Press [Enter] to proceed to the closure of workshop ..."

# Clean up
echo -e "\n${CYAN}=========================================================${NC}"
echo -e "🏁 WORKSHOP CONCLUDED - ADAM - 9739110917"
echo -e "${CYAN}=========================================================${NC}"
kind delete clusters wezvatech-lab
echo -e "${GREEN}[✔] KinD cluster returned cleanly to baseline conditions.${NC}"

