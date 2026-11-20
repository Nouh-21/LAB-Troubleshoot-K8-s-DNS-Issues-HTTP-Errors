#!/usr/bin/env bash

# ============================================================
# HTTP Troubleshooting Lab
# Environment: Windows + Docker Desktop + WSL2 + Kubernetes
# Uses an EXISTING Kubernetes cluster.
# Does not create or delete a Kind cluster.
# ============================================================

set -Eeuo pipefail

# -------------------------
# Configuration
# -------------------------

LAB_DIR="./lab"
NAMESPACE="${NAMESPACE:-default}"

HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-8443}"

INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
INGRESS_SERVICE="${INGRESS_SERVICE:-ingress-nginx-controller}"

INGRESS_NAME="wezva-ingress"
SERVICE_NAME="wezva-service"
DEPLOYMENT_NAME="wezva-deployment"

RUNTIME_DIR=".runtime"
PID_FILE="${RUNTIME_DIR}/port-forward.pid"
LOG_FILE="${RUNTIME_DIR}/port-forward.log"

KUBE_CONTEXT="${KUBE_CONTEXT:-}"

# Adapte ces noms si tes fichiers YAML portent d'autres noms.
SCENARIO_FILES=(
    ""
    "1-healthy-200.yaml"
    "2-redirect-301.yaml"
    "3-client-401.yaml"
    "4-client-404.yaml"
    "5-server-500.yaml"
    "6-badgateway-502.yaml"
    "7-serviceunavailable-503.yaml"
)

# -------------------------
# Colors
# -------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# -------------------------
# Display
# -------------------------

print_header() {
    clear
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "    🚀 WEZVATECH K8s HTTP HANDSHAKE WORKSHOP UTILITY     "
    echo -e "${CYAN}=========================================================${NC}"
}

clear_active_topology() {
    echo -e "${YELLOW}🧹 Clearing active scenario topology to avoid collisions...${NC}"
    kubectl delete deployment,service,ingress --all --grace-period=0 --force 2>/dev/null
    sleep 2
}

print_header() {
    clear 2>/dev/null || true

    echo -e "${BLUE}"
    echo "========================================================="
    echo "              HTTP TROUBLESHOOTING LAB"
    echo "========================================================="
    echo -e "${NC}"
    echo " Kubernetes context : ${KUBE_CONTEXT:-current}"
    echo " Namespace          : ${NAMESPACE}"
    echo " HTTP               : http://localhost:${HTTP_PORT}"
    echo " HTTPS              : https://localhost:${HTTPS_PORT}"
    echo "========================================================="
}

print_usage() {
    cat <<EOF

Usage:
  ./runme.sh --setup
  ./runme.sh --scenario-1
  ./runme.sh --scenario-2
  ./runme.sh --scenario-3
  ./runme.sh --scenario-4
  ./runme.sh --scenario-5
  ./runme.sh --scenario-6
  ./runme.sh --scenario-7
  ./runme.sh --cleanup
  ./runme.sh downOff
  ./runme.sh --downOff
  ./runme.sh --help

Options:
  KUBE_CONTEXT=<context>  Select a Kubernetes context.
  NAMESPACE=<namespace>   Select the lab namespace.
  HTTP_PORT=80           Local HTTP port.
  HTTPS_PORT=8443          Local HTTPS port.

Examples:
  ./runme.sh --setup
  ./runme.sh --scenario-1
  NAMESPACE=default ./runme.sh --cleanup

EOF
}

# -------------------------
# Kubernetes checks
# -------------------------

check_prerequisites() {
    echo -e "${YELLOW}🔍 Checking local infrastructure...${NC}"

    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}❌ kubectl is not accessible.${NC}"
        exit 1
    fi

    if [[ -z "${KUBE_CONTEXT}" ]]; then
        KUBE_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
    fi

    if [[ -z "${KUBE_CONTEXT}" ]]; then
        echo -e "${RED}❌ No active Kubernetes context found.${NC}"
        exit 1
    fi

    echo "Using Kubernetes context: ${KUBE_CONTEXT}"

    kubectl --context "${KUBE_CONTEXT}" cluster-info >/dev/null 2>&1 || {
        echo -e "${RED}❌ Kubernetes API is unreachable.${NC}"
        echo "Check Docker Desktop and Kubernetes status."
        exit 1
    }

    echo -e "${GREEN}✅ Kubernetes API is reachable.${NC}"

    kubectl --context "${KUBE_CONTEXT}" get nodes

    kubectl --context "${KUBE_CONTEXT}" get namespace "${NAMESPACE}" \
        >/dev/null 2>&1 || {
        echo -e "${RED}❌ Namespace '${NAMESPACE}' does not exist.${NC}"
        echo "Create it with: kubectl create namespace ${NAMESPACE}"
        exit 1
    }
}

check_lab_files() {
    echo -e "${YELLOW}🔍 Checking lab directory...${NC}"

    if [[ ! -d "${LAB_DIR}" ]]; then
        echo -e "${RED}❌ Directory ${LAB_DIR} not found.${NC}"
        exit 1
    fi

    local missing=0

    for i in {1..7}; do
        local file="${LAB_DIR}/${SCENARIO_FILES[$i]}"

        if [[ ! -f "${file}" ]]; then
            echo -e "${RED}❌ Missing manifest: ${file}${NC}"
            missing=1
        fi
    done

    if [[ "${missing}" -eq 1 ]]; then
        echo "Check the SCENARIO_FILES configuration in the script."
        exit 1
    fi

    echo -e "${GREEN}✅ Lab manifests found.${NC}"
}

check_ingress_controller() {
    echo -e "${YELLOW}🔍 Checking Ingress Controller...${NC}"

    local manifest="${LAB_DIR}/ingress_nginx_kind.yaml"

    if [[ ! -f "${manifest}" ]]; then
        echo -e "${RED}❌ Manifest not found: ${manifest}${NC}"
        exit 1
    fi

    # Check whether the controller already exists
    if kubectl --context "${KUBE_CONTEXT}" \
        -n "${INGRESS_NAMESPACE}" \
        get deployment ingress-nginx-controller >/dev/null 2>&1; then

        echo -e "${GREEN}✅ Ingress Controller already deployed.${NC}"

    else
        echo -e "${YELLOW}🚀 Deploying NGINX Ingress Controller...${NC}"

        kubectl --context "${KUBE_CONTEXT}" \
            apply -f "${manifest}"
    fi

    # Apply on every setup so existing deployments are repaired too.
    echo -e "${YELLOW}🚀 Applying NGINX Ingress configuration...${NC}"

    kubectl --context "${KUBE_CONTEXT}" \
        apply -f "${manifest}"

    echo "Waiting for Ingress Controller rollout..."

    kubectl --context "${KUBE_CONTEXT}" \
        -n "${INGRESS_NAMESPACE}" \
        rollout status deployment/ingress-nginx-controller \
        --timeout=180s

    echo -e "${GREEN}✅ Ingress Controller is ready.${NC}"

    kubectl --context "${KUBE_CONTEXT}" \
        -n "${INGRESS_NAMESPACE}" \
        get pods,services
}

# -------------------------
# Port forwarding
# -------------------------

stop_port_forward() {
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid="$(cat "${PID_FILE}")"

        if kill -0 "${pid}" 2>/dev/null; then
            echo "Stopping port-forward process ${pid}..."
            kill "${pid}" 2>/dev/null || true
        fi

        rm -f "${PID_FILE}"
    fi
}

start_port_forward() {
    echo -e "${YELLOW}🔍 Checking local access to Ingress...${NC}"

    mkdir -p "${RUNTIME_DIR}"

    # Reuse an already-running port-forward if possible.
    if curl -s --connect-timeout 2 \
        "http://localhost:${HTTP_PORT}" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ HTTP endpoint already reachable.${NC}"
        return
    fi

    stop_port_forward

    kubectl --context "${KUBE_CONTEXT}" \
        -n "${INGRESS_NAMESPACE}" \
        port-forward \
        "service/${INGRESS_SERVICE}" \
        "${HTTP_PORT}:80" \
        "${HTTPS_PORT}:443" \
        >"${LOG_FILE}" 2>&1 &

    local pid=$!
    echo "${pid}" > "${PID_FILE}"

    echo "Starting port-forward (PID: ${pid})..."

    for i in {1..15}; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            echo -e "${RED}❌ Port-forward failed.${NC}"
            cat "${LOG_FILE}"
            rm -f "${PID_FILE}"
            exit 1
        fi

        if curl -s --connect-timeout 1 \
            "http://localhost:${HTTP_PORT}" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Port-forward is ready.${NC}"
            return
        fi

        sleep 1
    done

    echo -e "${RED}❌ Cannot reach localhost:${HTTP_PORT}.${NC}"
    echo "Port-forward logs:"
    cat "${LOG_FILE}"
    stop_port_forward
    exit 1
}

# -------------------------
# Lab topology
# -------------------------

clear_active_topology() {
    echo -e "${YELLOW}🧹 Clearing previous lab topology...${NC}"

    # Delete only the scenario manifests. Never delete the Ingress Controller manifest.
    for i in {1..7}; do
        local manifest="${LAB_DIR}/${SCENARIO_FILES[$i]}"

        if [[ -f "${manifest}" ]]; then
            kubectl --context "${KUBE_CONTEXT}" \
                -n "${NAMESPACE}" \
                delete -f "${manifest}" \
                --ignore-not-found=true >/dev/null 2>&1 || true
        fi
    done

    echo -e "${GREEN}✅ Previous lab topology cleared.${NC}"
}

print_playbook_header() {
    echo -e "${YELLOW}⌛ Syncing cluster configuration assets...${NC}"
    sleep 3
    
    echo -e "\n${YELLOW}💡 WORKSHOP TROUBLESHOOTING PLAYBOOK:${NC}"
    echo -e "🔹 Step 1: Execute Client Request to Trigger the Error State"
    echo -e "    ${CYAN}curl -i http://localhost${NC}"
}

apply_scenario() {
    local scenario="$1"
    local manifest="${LAB_DIR}/${SCENARIO_FILES[$scenario]}"

    echo -e "${YELLOW}🚀 Deploying scenario ${scenario}...${NC}"

    clear_active_topology

    kubectl --context "${KUBE_CONTEXT}" \
        -n "${NAMESPACE}" \
        apply -f "${manifest}"

    echo -e "${GREEN}✅ Scenario ${scenario} deployed.${NC}"

    kubectl --context "${KUBE_CONTEXT}" \
        -n "${NAMESPACE}" \
        rollout status deployment/${DEPLOYMENT_NAME} --timeout=120s

    kubectl --context "${KUBE_CONTEXT}" \
        -n "${NAMESPACE}" get pods,services,ingress
}

get_pod_name() {
    kubectl --context "${KUBE_CONTEXT}" \
        -n "${NAMESPACE}" \
        get pods -l app=wezva-app \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}



show_http_test() {
    echo -e "${YELLOW}HTTP request:${NC}"
    curl -i --max-time 10 "http://localhost:${HTTP_PORT}/" || true
    echo
}

print_playbook_header() {
    echo -e "${YELLOW}⌛ Syncing cluster configuration assets...${NC}"
    sleep 3
    
    echo -e "\n${YELLOW}💡 WORKSHOP TROUBLESHOOTING PLAYBOOK:${NC}"
    echo -e "🔹 Step 1: Execute Client Request to Trigger the Error State"
    echo -e "    ${CYAN}curl -i http://localhost${NC}"
}


show_diagnostics() {
    echo -e "${YELLOW}Pods:${NC}"
    kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get pods -o wide

    echo
    echo -e "${YELLOW}Services:${NC}"
    kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get services

    echo
    echo -e "${YELLOW}Ingress:${NC}"
    kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" get ingress

    echo
    echo -e "${YELLOW}Recent events:${NC}"
    kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}" \
        get events --sort-by='.lastTimestamp' | tail -15

}



# -------------------------
# Scenario 1 - HTTP 200
# -------------------------



# -------------------------
# Setup
# -------------------------

setup_infrastructure() {
    print_header

    check_prerequisites
    check_lab_files
    check_ingress_controller

    echo -e "${YELLOW}🚀 Deploying the healthy baseline scenario...${NC}"
    apply_scenario 1

    start_port_forward

    echo
    echo -e "${GREEN}=========================================================${NC}"
    echo -e "${GREEN}✅ LAB READY${NC}"
    echo -e "${GREEN}=========================================================${NC}"
    echo "Existing Kubernetes cluster is being used."
    echo "No cluster was created or modified."
    echo "HTTP endpoint: http://localhost:${HTTP_PORT}"
}




run_scenario_1() {
    print_header; clear_active_topology
    echo -e "\n${GREEN}▶ SCENARIO 1: The Healthy Baseline (200 OK)${NC}\n"
    kubectl apply -f "$LAB_DIR/1-healthy-200.yaml"
    kubectl wait --for=condition=available --timeout=60s deployment --all 2>/dev/null
    sleep 3
    echo -e "${YELLOW}💡 STUDENT VERIFICATION STEP:${NC}"
    echo -e "👉 Test inside instance:\n    ${CYAN}curl -iv http://localhost${NC}"
    echo -e "👉 Test from external machine/browser:\n    ${CYAN}curl -iv http://$(curl -s checkip.amazonaws.com)${NC}\n"
}

run_scenario_2() {
    print_header; clear_active_topology
    echo -e "\n${GREEN}▶ SCENARIO 2: Protocol Redirection (301 Moved Permanently)${NC}\n"
    kubectl apply -f "$LAB_DIR/2-redirect-301.yaml"
    print_playbook_header
    echo -e "🔹 Step 2: Follow the Redirect Path Automatically (-L flag)\n    ${CYAN}curl -ivL http://localhost${NC}"
    echo -e "🔹 Step 3: Audit Ingress Redirect Rules Configuration\n    ${CYAN}kubectl get ingress wezva-ingress -o yaml | grep -A 2 annotations${NC}\n"
    echo -e "🔹 FIX THE PROBLEM: Remove annotation line from the Ingress resource\n    ${CYAN}kubectl annotate ingress wezva-ingress nginx.ingress.kubernetes.io/permanent-redirect-${NC}\n"
}

run_scenario_3() {
    print_header; clear_active_topology
    echo -e "\n${GREEN}▶ SCENARIO 3: Identity Authorization Deficiencies (401 Unauthorized)${NC}\n"
    kubectl apply -f "$LAB_DIR/3-client-401.yaml"
    #print_playbook_header
    #echo -e "🔹 Step 2: Inspect App Authorization Rejection Context\n    ${CYAN}kubectl logs $(kubectl get pods -l app=wezva-app -o jsonpath='{.items[0].metadata.name}')${NC}"
    #echo -e "🔹 FIX THE PROBLEM: Test with Authorization Header\n    ${CYAN}curl -iv -H 'Authorization: Bearer secret-token' http://localhost${NC}\n"
}

run_scenario_4() {
    print_header; clear_active_topology
    echo -e "\n${GREEN}▶ SCENARIO 4: Missing Endpoints / Assets (404 Not Found)${NC}\n"
    kubectl apply -f "$LAB_DIR/4-client-404.yaml"
    #print_playbook_header
    #echo -e "🔹 Step 2: Check Application Server Logs for Unmapped Routes\n    ${CYAN}kubectl logs $(kubectl get pods -l app=wezva-app -o jsonpath='{.items[0].metadata.name}')${NC}\n"
    #echo -e "🔹 FIX THE PROBLEM: Curl the target with the Endpoint\n    ${CYAN}curl -i http://localhost/healthz${NC}\n"
}

run_scenario_5() {
    print_header; clear_active_topology
    echo -e "\n${GREEN}▶ SCENARIO 5: Application Exceptions (500 Internal Server Error)${NC}\n"
    kubectl apply -f "$LAB_DIR/5-server-500.yaml"
    #print_playbook_header
    #echo -e "🔹 Step 2: Check Application Server Logs for Crash Log Trace\n    ${CYAN}kubectl logs $(kubectl get pods -l app=wezva-app -o jsonpath='{.items[0].metadata.name}')${NC}\n"
    #echo -e "🔹 FIX THE PROBLEM: Inject Environment Variable \n    ${CYAN}kubectl set env deployment/wezva-deployment DATABASE_URL="postgres://user:pass@db:5432/wezva"${NC}\n"
}

run_scenario_6() {
    print_header; clear_active_topology
    echo -e "\n${GREEN}▶ SCENARIO 6: Immediate Runtime Crashes (502 Bad Gateway)${NC}\n"
    kubectl apply -f "$LAB_DIR/6-badgateway-502.yaml"
    #print_playbook_header
    #echo -e "🔹 Step 2: Validate Service Endpoints & Port Mappings \n    ${CYAN}kubectl get endpoints wezva-service${NC}"
    #echo -e "🔹 Step 3: Check Ingress Proxy Controller Error Sockets\n    ${CYAN}kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20 | grep -i error${NC}\n"
    #echo -e "🔹 FIX THE PROBLEM: Patch the service to Target port 8080 \n    ${CYAN}kubectl patch service wezva-service --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8080}]' \n    kubectl annotate ingress wezva-ingress ingress.kubernetes.io/reload="$(date +%s)" --overwrite ${NC}\n"
}

run_scenario_7() {
    print_header; clear_active_topology
    echo -e "\n${GREEN}▶ SCENARIO 7: Infrastructure Orchestration Dropouts (503 Service Unavailable)${NC}\n"
    kubectl apply -f "$LAB_DIR/7-serviceunavailable-503.yaml"
    echo -e "${YELLOW}🔧 Injecting intentional Service Selector Mismatch...${NC}"
    sleep 2
    kubectl patch service wezva-service -p '{"spec":{"selector":{"app":"fallback-handler"}}}' 2>/dev/null
    #print_playbook_header
    #echo -e "🔹 Step 2: Verify Missing active Service Endpoints (Will show '<none>')\n    ${CYAN}kubectl get endpoints wezva-service${NC}"
    #echo -e "🔹 Step 3: Check Pod Label Selectors and Health Status\n    ${CYAN}kubectl get pods --show-labels${NC}\n"
    #echo -e "🔹 FIX THE PROBLEM: Apply the correct label selector on the service \n    ${CYAN}kubectl patch service wezva-service -p '{\"spec\":{\"selector\":{\"app\":\"wezva-app\"}}}'${NC}\n"
}

# -------------------------
# Cleanup
# -------------------------

cleanup_environment() {
    print_header

    check_prerequisites

    echo -e "${YELLOW}🧹 Cleaning lab resources...${NC}"

    clear_active_topology
    stop_port_forward

    echo
    echo -e "${GREEN}✅ Lab resources cleaned.${NC}"
    echo "Your Docker Desktop Kubernetes cluster is preserved."
}

power_off_environment() {
    print_header

    check_prerequisites

    echo -e "${YELLOW}🛑 Stopping port-forward and releasing lab memory...${NC}"

    stop_port_forward
    clear_active_topology

    kubectl --context "${KUBE_CONTEXT}" \
        delete namespace "${INGRESS_NAMESPACE}" \
        --ignore-not-found=true \
        --wait=true --timeout=120s || true

    kubectl --context "${KUBE_CONTEXT}" \
        delete clusterrole ingress-nginx \
        --ignore-not-found=true >/dev/null 2>&1 || true

    kubectl --context "${KUBE_CONTEXT}" \
        delete clusterrolebinding ingress-nginx \
        --ignore-not-found=true >/dev/null 2>&1 || true

    kubectl --context "${KUBE_CONTEXT}" \
        delete ingressclass nginx \
        --ignore-not-found=true >/dev/null 2>&1 || true

    rm -rf "${RUNTIME_DIR}"

    echo
    echo -e "${GREEN}=========================================================${NC}"
    echo -e "${GREEN}✅ LAB RESOURCES REMOVED${NC}"
    echo -e "${GREEN}=========================================================${NC}"
    echo "Application scenarios removed: namespace ${NAMESPACE}"
    echo "Ingress Controller removed: namespace ${INGRESS_NAMESPACE}"
    echo "RBAC and IngressClass removed."
    echo "Kubernetes cluster preserved."
}

print_scenario_playbook() {
    local scenario="$1"

    echo
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${YELLOW}STUDENT DEBUGGING PLAYBOOK${NC}"
    echo -e "${CYAN}=========================================================${NC}"

    echo "Step 1: Test the HTTP response"
    echo "  curl -iv http://localhost:${HTTP_PORT}/"

    case "${scenario}" in
        1)
            echo
            echo "Step 2: Verify the complete path"
            echo "  kubectl get pods,services,ingress -n ${NAMESPACE}"
            echo "  kubectl get endpoints ${SERVICE_NAME} -n ${NAMESPACE}"
            echo
            echo "Expected result: HTTP 200 OK"
            echo "No corrective action is normally required."
            ;;
        2)
            echo
            echo "Step 2: Follow and inspect the redirect"
            echo "  curl -IL http://localhost:${HTTP_PORT}/"
            echo "  kubectl get ingress ${INGRESS_NAME} -n ${NAMESPACE} -o yaml"
            echo
            echo "Fix: remove the permanent redirect annotation"
            echo "  kubectl annotate ingress ${INGRESS_NAME} -n ${NAMESPACE} nginx.ingress.kubernetes.io/permanent-redirect-"
            ;;
        3)
            echo
            echo "Step 2: Test with and without authentication"
            echo "  curl -iv http://localhost:${HTTP_PORT}/"
            echo "  curl -iv -H 'Authorization: Bearer secret-token' http://localhost:${HTTP_PORT}/"
            echo "  kubectl describe ingress ${INGRESS_NAME} -n ${NAMESPACE}"
            echo
            echo "Fix: provide the valid bearer token or correct application authentication."
            ;;
        4)
            echo
            echo "Step 2: Compare the missing route with a valid route"
            echo "  curl -iv http://localhost:${HTTP_PORT}/"
            echo "  curl -iv http://localhost:${HTTP_PORT}/healthz"
            echo "  kubectl logs -n ${NAMESPACE} -l app=wezva-app --tail=50"
            echo
            echo "Fix: add the missing application route or request /healthz for the available endpoint."
            ;;
        5)
            echo
            echo "Step 2: Trigger the exception and inspect application logs"
            echo "  curl -iv http://localhost:${HTTP_PORT}/database"
            echo "  kubectl logs -n ${NAMESPACE} -l app=wezva-app --tail=100"
            echo
            echo "Fix: provide the missing DATABASE_URL environment variable"
            echo "  kubectl set env deployment/${DEPLOYMENT_NAME} -n ${NAMESPACE} DATABASE_URL=postgres://user:pass@db:5432/wezva"
            ;;
        6)
            echo
            echo "Step 2: Inspect the Service and endpoints"
            echo "  kubectl describe service ${SERVICE_NAME} -n ${NAMESPACE}"
            echo "  kubectl get endpoints ${SERVICE_NAME} -n ${NAMESPACE}"
            echo
            echo "Fix: route the Service to the Pod port 80"
            echo "  kubectl patch service ${SERVICE_NAME} -n ${NAMESPACE} --type='json' -p='[{\"op\":\"replace\",\"path\":\"/spec/ports/0/targetPort\",\"value\":80}]'"
            ;;
        7)
            echo
            echo "Step 2: Verify that no endpoint matches the Service"
            echo "  kubectl get endpoints ${SERVICE_NAME} -n ${NAMESPACE}"
            echo "  kubectl get pods --show-labels -n ${NAMESPACE}"
            echo "  kubectl describe service ${SERVICE_NAME} -n ${NAMESPACE}"
            echo
            echo "Fix: restore the Service selector"
            echo "  kubectl patch service ${SERVICE_NAME} -n ${NAMESPACE} -p '{\"spec\":{\"selector\":{\"app\":\"wezva-app\"}}}'"
            echo "  kubectl -n default annotate ingress ${INGRESS_NAME} ingress.kubernetes.io/reload=\"$(date +%s)\" --overwrite"
            echo " kubectl -n ${NAMESPACE} rollout restart deployment/wezva-deployment; kubectl -n ${NAMESPACE} rollout status deployment/wezva-deployment"
            ;;
    esac

    echo
}

print_mode_emploi_1() {
    print_scenario_playbook 1
}

print_mode_emploi_2() {
    print_scenario_playbook 2
}

print_mode_emploi_3() {
    print_scenario_playbook 3
}

print_mode_emploi_4() {
    print_scenario_playbook 4
}

print_mode_emploi_5() {
    print_scenario_playbook 5
}

print_mode_emploi_6() {
    print_scenario_playbook 6
}

print_mode_emploi_7() {
    print_scenario_playbook 7
}
# -------------------------
# Main
# -------------------------

case "${1:---help}" in
    --setup)
        setup_infrastructure
        ;;
    --scenario-1)
        #check_prerequisites
        run_scenario_1
        print_mode_emploi_1
        ;;
    --scenario-2)
        #check_prerequisites
        run_scenario_2
        print_mode_emploi_2
        ;;
    --scenario-3)
        #check_prerequisites
        run_scenario_3
        print_mode_emploi_3
        ;;
    --scenario-4)
        check_prerequisites
        run_scenario_4
        print_mode_emploi_4
        ;;
    --scenario-5)
        #check_prerequisites
        run_scenario_5
        print_mode_emploi_5
        ;;
    --scenario-6)
        #check_prerequisites
        run_scenario_6
        print_mode_emploi_6
        ;;
    --scenario-7)
        #check_prerequisites
        run_scenario_7
        print_mode_emploi_7
        ;;
    --cleanup)
        cleanup_environment
        ;;
    downOff|--downOff)
        power_off_environment
        ;;
    --help|-h)
        print_usage
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        print_usage
        exit 1
        ;;
esac
