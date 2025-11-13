#!/bin/bash

# Istio 설치 스크립트
# 
# 이 스크립트는 다음을 수행합니다:
# 1. Istio Operator 설치
# 2. Istio Control Plane 배포
# 3. Gateway API CRD 설치
# 4. Istio 구성 리소스 배포

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 변수
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISTIO_VERSION="${ISTIO_VERSION:-1.22.0}"
NAMESPACE="${NAMESPACE:-ecommerce}"
ISTIO_NAMESPACE="istio-system"

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 필수 도구 확인
check_prerequisites() {
    log_step "필수 도구 확인 중..."
    
    local missing_tools=()
    
    for tool in kubectl istioctl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "다음 도구들이 설치되어 있지 않습니다: ${missing_tools[*]}"
        log_info "istioctl 설치: curl -L https://istio.io/downloadIstio | sh -"
        exit 1
    fi
    
    log_info "모든 필수 도구가 설치되어 있습니다."
}

# Istio 설치 확인
check_istio_installed() {
    if kubectl get namespace "$ISTIO_NAMESPACE" &> /dev/null; then
        log_warn "Istio가 이미 설치되어 있습니다."
        read -p "재설치하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "설치를 건너뜁니다."
            return 1
        fi
        return 0
    fi
    return 0
}

# Istio 설치
install_istio() {
    log_step "Istio ${ISTIO_VERSION} 설치 중..."
    
    # Istio 네임스페이스 생성
    kubectl create namespace "$ISTIO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Istio Operator 설치
    istioctl install \
        --set values.defaultRevision=default \
        --set profile=minimal \
        -y
    
    log_info "Istio Control Plane 설치 완료"
    
    # Istio 설치 확인
    log_step "Istio 설치 확인 중..."
    kubectl wait --for=condition=ready pod -l app=istiod -n "$ISTIO_NAMESPACE" --timeout=300s || {
        log_error "Istio Control Plane이 준비되지 않았습니다."
        exit 1
    }
    
    log_info "Istio Control Plane이 준비되었습니다."
}

# Gateway API CRD 설치
install_gateway_api() {
    log_step "Gateway API CRD 설치 중..."
    
    # Gateway API 버전 확인 및 설치
    GATEWAY_API_VERSION="v1.0.0"
    
    kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
    
    log_info "Gateway API CRD 설치 완료"
    
    # Gateway API 설치 확인
    log_step "Gateway API 설치 확인 중..."
    sleep 5
    if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
        log_info "Gateway API가 설치되었습니다."
    else
        log_error "Gateway API 설치에 실패했습니다."
        exit 1
    fi
}

# Istio Gateway Class 설치
install_istio_gateway_class() {
    log_step "Istio Gateway Class 설치 중..."
    
    kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
EOF
    
    log_info "Istio Gateway Class 설치 완료"
}

# E-commerce 네임스페이스 생성 및 라벨링
setup_namespace() {
    log_step "E-commerce 네임스페이스 설정 중..."
    
    # 네임스페이스 생성
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Istio 자동 주입 활성화
    kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite || true
    
    log_info "네임스페이스 '$NAMESPACE' 설정 완료"
}

# Istio 구성 리소스 배포
deploy_istio_resources() {
    log_step "Istio 구성 리소스 배포 중..."
    
    local resources_dir="${SCRIPT_DIR}/resources"
    
    if [ ! -d "$resources_dir" ]; then
        log_error "리소스 디렉토리를 찾을 수 없습니다: $resources_dir"
        exit 1
    fi
    
    # 리소스 배포 순서
    local deploy_order=(
        "00-gateway-class.yaml"
        "01-peer-authentication.yaml"
        "02-gateway-main.yaml"
        "03-gateway-webhook.yaml"
        "04-httproute-*.yaml"
        "05-request-authentication.yaml"
        "05-virtual-service-retry-timeout.yaml"
        "06-authorization-policy.yaml"
        "07-destination-rule-*.yaml"
        "08-envoy-filter-*.yaml"
    )
    
    for pattern in "${deploy_order[@]}"; do
        for file in "$resources_dir"/$pattern; do
            if [ -f "$file" ]; then
                log_info "배포 중: $(basename "$file")"
                kubectl apply -f "$file" -n "$NAMESPACE" || {
                    log_warn "배포 실패 (계속 진행): $(basename "$file")"
                }
            fi
        done
    done
    
    log_info "Istio 구성 리소스 배포 완료"
}

# 메인 함수
main() {
    log_step "=== Istio 설치 시작 ==="
    
    check_prerequisites
    
    if check_istio_installed; then
        install_istio
    fi
    
    install_gateway_api
    install_istio_gateway_class
    setup_namespace
    deploy_istio_resources
    
    log_step "=== Istio 설치 완료 ==="
    log_info ""
    log_info "다음 명령어로 Istio 상태를 확인하세요:"
    log_info "  kubectl get pods -n $ISTIO_NAMESPACE"
    log_info "  istioctl verify-install"
    log_info "  kubectl get gateway -n $NAMESPACE"
}

# 스크립트 실행
main "$@"

