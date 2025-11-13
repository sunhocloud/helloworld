#!/bin/bash

# Istio 테스트 스크립트 (EKS 환경)
# 
# 이 스크립트는 다음을 테스트합니다:
# 1. Istio 설치 상태 확인
# 2. 테스트 애플리케이션 배포
# 3. Gateway를 통한 트래픽 테스트
# 4. mTLS 확인

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 변수
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-ecommerce}"
ISTIO_NAMESPACE="istio-system"
TEST_APP_NAME="httpbin"

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

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

# istioctl 찾기
find_istioctl() {
    if command -v istioctl &> /dev/null; then
        return 0
    fi
    
    local search_dirs=(
        "$SCRIPT_DIR"
        "$(dirname "$SCRIPT_DIR")"
        "$(dirname "$(dirname "$SCRIPT_DIR")")"
        "$HOME"
    )
    
    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            for istio_dir in "$dir"/istio-*/bin/istioctl; do
                if [ -f "$istio_dir" ] && [ -x "$istio_dir" ]; then
                    export PATH="$(dirname "$istio_dir"):$PATH"
                    return 0
                fi
            done
        fi
    done
    
    return 1
}

# 1. Istio 설치 상태 확인
check_istio_status() {
    log_step "=== Istio 설치 상태 확인 ==="
    
    local all_ok=true
    
    # Istio 네임스페이스 확인
    if kubectl get namespace "$ISTIO_NAMESPACE" &> /dev/null; then
        log_success "Istio 네임스페이스 존재"
    else
        log_fail "Istio 네임스페이스 없음"
        all_ok=false
    fi
    
    # Istio Control Plane Pod 확인
    log_info "Istio Control Plane Pod 확인 중..."
    if kubectl get pods -n "$ISTIO_NAMESPACE" -l app=istiod --no-headers 2>/dev/null | grep -q Running; then
        log_success "Istio Control Plane 실행 중"
        kubectl get pods -n "$ISTIO_NAMESPACE" -l app=istiod
    else
        log_fail "Istio Control Plane 실행 안 됨"
        all_ok=false
    fi
    
    # Gateway Pod 확인 (Gateway API 사용 시 ecommerce 네임스페이스에 생성됨)
    log_info "Istio Gateway Pod 확인 중..."
    local gateway_pods
    gateway_pods=$(kubectl get pods -n "$NAMESPACE" -l gateway.networking.k8s.io/gateway-name --no-headers 2>/dev/null | grep -i gateway | grep Running || echo "")
    
    if [ -n "$gateway_pods" ]; then
        log_success "Istio Gateway Pod 실행 중"
        kubectl get pods -n "$NAMESPACE" -l gateway.networking.k8s.io/gateway-name
    else
        # 기존 방식 확인 (istio-system 네임스페이스)
        if kubectl get pods -n "$ISTIO_NAMESPACE" -l app=istio-ingressgateway --no-headers 2>/dev/null | grep -q Running; then
            log_success "Istio Ingress Gateway 실행 중 (기존 방식)"
            kubectl get pods -n "$ISTIO_NAMESPACE" -l app=istio-ingressgateway
        else
            log_warn "Gateway Pod를 찾을 수 없습니다. Gateway 리소스 상태를 확인하세요."
        fi
    fi
    
    # LoadBalancer 주소 확인 (Gateway 리소스의 ADDRESS 사용)
    log_info "LoadBalancer 주소 확인 중..."
    local lb_hostname
    # Gateway API를 사용하는 경우 Gateway 리소스의 status.addresses에서 가져옴
    lb_hostname=$(kubectl get gateway ecommerce-gateway -n "$NAMESPACE" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    
    # Gateway 리소스에 주소가 없으면 서비스에서 확인
    if [ -z "$lb_hostname" ]; then
        # Gateway API 방식: ecommerce 네임스페이스의 서비스 확인
        lb_hostname=$(kubectl get svc -n "$NAMESPACE" ecommerce-gateway-istio -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    fi
    
    # 기존 방식 확인
    if [ -z "$lb_hostname" ]; then
        lb_hostname=$(kubectl get svc -n "$ISTIO_NAMESPACE" istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    fi
    
    if [ -n "$lb_hostname" ]; then
        log_success "LoadBalancer 주소: $lb_hostname"
        export GATEWAY_HOST="$lb_hostname"
    else
        log_warn "LoadBalancer 주소가 아직 할당되지 않았습니다. 잠시 후 다시 확인하세요."
        log_info "확인 명령어: kubectl get gateway -n $NAMESPACE"
        log_info "또는: kubectl get svc -n $NAMESPACE ecommerce-gateway-istio"
        export GATEWAY_HOST=""
    fi
    
    # Gateway 리소스 확인
    log_info "Gateway 리소스 확인 중..."
    if kubectl get gateway -n "$NAMESPACE" &> /dev/null; then
        log_success "Gateway 리소스 존재"
        kubectl get gateway -n "$NAMESPACE"
    else
        log_warn "Gateway 리소스 없음 (네임스페이스: $NAMESPACE)"
    fi
    
    # HTTPRoute 확인
    log_info "HTTPRoute 리소스 확인 중..."
    if kubectl get httproute -n "$NAMESPACE" &> /dev/null; then
        local route_count
        route_count=$(kubectl get httproute -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$route_count" -gt 0 ]; then
            log_success "HTTPRoute 리소스 $route_count 개 존재"
            kubectl get httproute -n "$NAMESPACE"
        else
            log_warn "HTTPRoute 리소스 없음"
        fi
    else
        log_warn "HTTPRoute 리소스 없음"
    fi
    
    if [ "$all_ok" = true ]; then
        log_success "Istio 설치 상태 정상"
        return 0
    else
        log_error "Istio 설치 상태에 문제가 있습니다."
        return 1
    fi
}

# 2. 테스트 애플리케이션 배포
deploy_test_app() {
    log_step "=== 테스트 애플리케이션 배포 ==="
    
    # 네임스페이스 확인
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "네임스페이스 생성 중: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
        kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite
    fi
    
    # httpbin 배포 (테스트용 HTTP 서버)
    log_info "httpbin 배포 중..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${TEST_APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${TEST_APP_NAME}
spec:
  ports:
  - name: http
    port: 8000
    targetPort: 80
  selector:
    app: ${TEST_APP_NAME}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TEST_APP_NAME}
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${TEST_APP_NAME}
  template:
    metadata:
      labels:
        app: ${TEST_APP_NAME}
    spec:
      containers:
      - image: kennethreitz/httpbin:latest
        imagePullPolicy: IfNotPresent
        name: ${TEST_APP_NAME}
        ports:
        - containerPort: 80
EOF
    
    log_info "httpbin 배포 완료. Pod 준비 대기 중..."
    kubectl wait --for=condition=ready pod -l app="${TEST_APP_NAME}" -n "$NAMESPACE" --timeout=120s || {
        log_error "httpbin Pod가 준비되지 않았습니다."
        return 1
    }
    
    log_success "테스트 애플리케이션 배포 완료"
    kubectl get pods -n "$NAMESPACE" -l app="${TEST_APP_NAME}"
}

# 3. 테스트용 HTTPRoute 생성
create_test_route() {
    log_step "=== 테스트용 HTTPRoute 생성 ==="
    
    # 테스트용 HTTPRoute 생성
    kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${TEST_APP_NAME}-route
  namespace: ${NAMESPACE}
spec:
  parentRefs:
    - name: ecommerce-gateway
  hostnames:
    - "api.ecommerce.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /test
      backendRefs:
        - name: ${TEST_APP_NAME}
          port: 8000
          weight: 100
EOF
    
    log_success "테스트용 HTTPRoute 생성 완료"
    kubectl get httproute "${TEST_APP_NAME}-route" -n "$NAMESPACE"
}

# 4. Gateway를 통한 트래픽 테스트
test_gateway_traffic() {
    log_step "=== Gateway를 통한 트래픽 테스트 ==="
    
    if [ -z "${GATEWAY_HOST:-}" ]; then
        log_warn "LoadBalancer 주소가 없어 Gateway 테스트를 건너뜁니다."
        log_info "LoadBalancer 주소 확인: kubectl get svc -n $ISTIO_NAMESPACE istio-ingressgateway"
        return 1
    fi
    
    log_info "Gateway 주소: $GATEWAY_HOST"
    log_info "테스트 엔드포인트: http://${GATEWAY_HOST}/test/get"
    
    # Host 헤더를 사용한 테스트
    log_info "HTTP 요청 테스트 중..."
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Host: api.ecommerce.com" \
        "http://${GATEWAY_HOST}/test/get" || echo "000")
    
    if [ "$response" = "200" ]; then
        log_success "Gateway 트래픽 테스트 성공 (HTTP $response)"
        
        # 상세 응답 확인
        log_info "상세 응답 확인:"
        curl -s -H "Host: api.ecommerce.com" "http://${GATEWAY_HOST}/test/get" | head -20
    elif [ "$response" = "000" ]; then
        log_warn "Gateway에 연결할 수 없습니다. LoadBalancer가 아직 준비 중일 수 있습니다."
        log_info "잠시 후 다시 시도하세요: curl -H 'Host: api.ecommerce.com' http://${GATEWAY_HOST}/test/get"
    else
        log_warn "Gateway 트래픽 테스트 실패 (HTTP $response)"
        log_info "응답 확인: curl -v -H 'Host: api.ecommerce.com' http://${GATEWAY_HOST}/test/get"
    fi
}

# 5. mTLS 확인
check_mtls() {
    log_step "=== mTLS 확인 ==="
    
    if ! find_istioctl; then
        log_warn "istioctl을 찾을 수 없어 mTLS 확인을 건너뜁니다."
        return 1
    fi
    
    # PeerAuthentication 확인
    log_info "PeerAuthentication 확인 중..."
    if kubectl get peerauthentication -n "$NAMESPACE" &> /dev/null; then
        log_success "PeerAuthentication 설정 존재"
        kubectl get peerauthentication -n "$NAMESPACE" -o yaml | grep -A 5 "mtls:"
    else
        log_warn "PeerAuthentication 설정 없음"
    fi
    
    # Pod의 mTLS 상태 확인
    local test_pod
    test_pod=$(kubectl get pods -n "$NAMESPACE" -l app="${TEST_APP_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$test_pod" ]; then
        log_info "Pod mTLS 상태 확인: $test_pod"
        if istioctl proxy-config secret "${test_pod}.${NAMESPACE}" &> /dev/null; then
            log_success "Pod에 mTLS 인증서가 설정되어 있습니다."
        else
            log_warn "Pod에 mTLS 인증서가 없습니다."
        fi
    else
        log_warn "테스트 Pod를 찾을 수 없습니다."
    fi
}

# 6. 정리 (선택사항)
cleanup_test_app() {
    log_step "=== 테스트 애플리케이션 정리 ==="
    
    read -p "테스트 애플리케이션을 삭제하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "테스트 애플리케이션 삭제 중..."
        kubectl delete httproute "${TEST_APP_NAME}-route" -n "$NAMESPACE" --ignore-not-found=true
        kubectl delete deployment "${TEST_APP_NAME}" -n "$NAMESPACE" --ignore-not-found=true
        kubectl delete service "${TEST_APP_NAME}" -n "$NAMESPACE" --ignore-not-found=true
        log_success "테스트 애플리케이션 삭제 완료"
    else
        log_info "테스트 애플리케이션을 유지합니다."
    fi
}

# 메인 함수
main() {
    log_step "=== Istio 테스트 시작 ==="
    
    # istioctl 찾기
    if ! find_istioctl; then
        log_warn "istioctl을 찾을 수 없습니다. 일부 테스트가 제한될 수 있습니다."
    fi
    
    # 1. Istio 설치 상태 확인
    check_istio_status
    
    echo ""
    
    # 2. 테스트 애플리케이션 배포
    if deploy_test_app; then
        echo ""
        
        # 3. 테스트용 HTTPRoute 생성
        create_test_route
        echo ""
        
        # 4. Gateway 트래픽 테스트
        log_info "HTTPRoute가 적용될 때까지 10초 대기 중..."
        sleep 10
        test_gateway_traffic
        echo ""
        
        # 5. mTLS 확인
        check_mtls
        echo ""
    fi
    
    # 요약
    log_step "=== 테스트 요약 ==="
    log_info "다음 명령어로 추가 확인:"
    log_info "  # Gateway 상태: kubectl get gateway -n $NAMESPACE"
    log_info "  # HTTPRoute 상태: kubectl get httproute -n $NAMESPACE"
    log_info "  # Pod 상태: kubectl get pods -n $NAMESPACE"
    log_info "  # LoadBalancer 주소: kubectl get svc -n $ISTIO_NAMESPACE istio-ingressgateway"
    
    if [ -n "${GATEWAY_HOST:-}" ]; then
        log_info ""
        log_info "수동 테스트 명령어:"
        log_info "  curl -H 'Host: api.ecommerce.com' http://${GATEWAY_HOST}/test/get"
        log_info "  curl -H 'Host: api.ecommerce.com' http://${GATEWAY_HOST}/test/status/200"
    fi
    
    echo ""
    
    # 정리 옵션
    cleanup_test_app
    
    log_step "=== 테스트 완료 ==="
}

# 스크립트 실행
main "$@"

