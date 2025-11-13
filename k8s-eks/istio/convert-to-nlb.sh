#!/bin/bash

# Classic Load Balancer를 NLB로 변경하는 스크립트

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-ecommerce}"

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

# Gateway Service에 NLB 어노테이션 추가
add_nlb_annotations() {
    log_step "NLB 어노테이션 추가 중..."
    
    local services=(
        "ecommerce-gateway-istio"
        "webhook-gateway-istio"
    )
    
    for svc in "${services[@]}"; do
        if kubectl get svc "$svc" -n "$NAMESPACE" &> /dev/null; then
            log_info "Service 어노테이션 추가: $svc"
            kubectl annotate svc "$svc" -n "$NAMESPACE" \
                service.beta.kubernetes.io/aws-load-balancer-type=nlb \
                service.beta.kubernetes.io/aws-load-balancer-scheme=internet-facing \
                service.beta.kubernetes.io/aws-load-balancer-nlb-target-type=ip \
                --overwrite || log_warn "어노테이션 추가 실패: $svc"
        fi
    done
}

# Service 재생성 (NLB로 변경)
recreate_services() {
    log_step "Service 재생성 중 (NLB로 변경)..."
    
    log_warn "기존 Classic Load Balancer가 삭제되고 NLB가 생성됩니다."
    log_warn "이 과정에서 일시적인 다운타임이 발생할 수 있습니다."
    
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "취소되었습니다."
        exit 0
    fi
    
    local services=(
        "ecommerce-gateway-istio"
        "webhook-gateway-istio"
    )
    
    for svc in "${services[@]}"; do
        if kubectl get svc "$svc" -n "$NAMESPACE" &> /dev/null; then
            log_info "Service 삭제 중: $svc"
            kubectl delete svc "$svc" -n "$NAMESPACE"
            
            log_info "Istio가 Service를 재생성할 때까지 대기 중..."
            sleep 5
            
            # Istio가 Service를 재생성할 때까지 대기
            local max_attempts=30
            local attempt=0
            while [ $attempt -lt $max_attempts ]; do
                if kubectl get svc "$svc" -n "$NAMESPACE" &> /dev/null; then
                    log_info "Service 재생성 완료: $svc"
                    break
                fi
                attempt=$((attempt + 1))
                sleep 2
            done
            
            if [ $attempt -eq $max_attempts ]; then
                log_error "Service 재생성 실패: $svc"
                log_info "Gateway를 재생성해보세요: kubectl delete gateway <gateway-name> -n $NAMESPACE && kubectl apply -f resources/02-gateway-main.yaml"
            fi
        fi
    done
}

# Gateway 재생성 (더 안전한 방법)
recreate_gateways() {
    log_step "Gateway 재생성 중 (NLB로 변경)..."
    
    log_warn "Gateway를 재생성하면 Service도 함께 재생성됩니다."
    log_warn "이 과정에서 일시적인 다운타임이 발생할 수 있습니다."
    
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "취소되었습니다."
        exit 0
    fi
    
    # Gateway 백업
    log_info "Gateway 리소스 백업 중..."
    kubectl get gateway ecommerce-gateway -n "$NAMESPACE" -o yaml > /tmp/ecommerce-gateway-backup.yaml
    kubectl get gateway webhook-gateway -n "$NAMESPACE" -o yaml > /tmp/webhook-gateway-backup.yaml 2>/dev/null || true
    
    # Gateway 삭제 (Service도 함께 삭제됨)
    log_info "Gateway 삭제 중..."
    kubectl delete gateway ecommerce-gateway -n "$NAMESPACE"
    kubectl delete gateway webhook-gateway -n "$NAMESPACE" 2>/dev/null || true
    
    # Gateway 재생성
    log_info "Gateway 재생성 중..."
    kubectl apply -f resources/02-gateway-main.yaml
    kubectl apply -f resources/03-gateway-webhook.yaml 2>/dev/null || true
    
    log_info "Gateway 재생성 완료. NLB가 생성될 때까지 몇 분이 걸릴 수 있습니다."
}

# 메인 함수
main() {
    log_step "=== Classic Load Balancer를 NLB로 변경 ==="
    
    echo ""
    log_info "두 가지 방법이 있습니다:"
    echo "  1. Service만 재생성 (빠름, 하지만 Istio가 자동으로 재생성하지 않을 수 있음)"
    echo "  2. Gateway 재생성 (권장, Istio가 Service를 자동으로 재생성)"
    echo ""
    
    read -p "방법을 선택하세요 (1 또는 2, 기본값: 2): " method
    method=${method:-2}
    
    # 어노테이션 추가
    add_nlb_annotations
    
    echo ""
    
    if [ "$method" = "1" ]; then
        recreate_services
    else
        recreate_gateways
    fi
    
    echo ""
    log_step "=== 완료 ==="
    log_info "NLB 주소 확인:"
    log_info "  kubectl get svc -n $NAMESPACE ecommerce-gateway-istio"
    log_info ""
    log_info "NLB가 준비될 때까지 몇 분이 걸릴 수 있습니다."
    log_info "확인 명령어: kubectl get svc -n $NAMESPACE -w"
}

main "$@"

