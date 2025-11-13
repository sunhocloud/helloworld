#!/bin/bash

# 로컬 k3d 환경 중지 스크립트
# 
# 이 스크립트는 다음을 수행합니다:
# 1. Helm 릴리스 제거 (선택적)
# 2. k3d 클러스터 중지 또는 삭제 (선택적)

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 변수
CLUSTER_NAME="${CLUSTER_NAME:-msa-quality-cluster}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3D_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_FILE="${K3D_DIR}/kubeconfig/config"
NAMESPACE="${NAMESPACE:-msa-quality}"

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

# Helm 릴리스 제거
uninstall_helm_releases() {
    log_step "Helm 릴리스 제거 중..."
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    if ! kubectl cluster-info &> /dev/null; then
        log_warn "클러스터에 연결할 수 없습니다. Helm 릴리스 제거를 건너뜁니다."
        return 0
    fi
    
    # 네임스페이스의 모든 Helm 릴리스 확인
    local releases
    releases=$(helm list -n "${NAMESPACE}" --short 2>/dev/null || echo "")
    
    if [ -z "$releases" ]; then
        log_info "제거할 Helm 릴리스가 없습니다."
        return 0
    fi
    
    log_info "다음 Helm 릴리스를 제거합니다:"
    echo "$releases"
    
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Helm 릴리스 제거를 취소했습니다."
        return 0
    fi
    
    # 각 릴리스 제거
    while IFS= read -r release; do
        if [ -n "$release" ]; then
            log_info "릴리스 '${release}' 제거 중..."
            helm uninstall "$release" -n "${NAMESPACE}" || {
                log_warn "릴리스 '${release}' 제거 실패 (계속 진행)"
            }
        fi
    done <<< "$releases"
    
    log_info "Helm 릴리스 제거 완료"
}

# 네임스페이스 삭제
delete_namespace() {
    log_step "네임스페이스 삭제 중..."
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    if ! kubectl cluster-info &> /dev/null; then
        log_warn "클러스터에 연결할 수 없습니다. 네임스페이스 삭제를 건너뜁니다."
        return 0
    fi
    
    if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        read -p "네임스페이스 '${NAMESPACE}'를 삭제하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete namespace "${NAMESPACE}" --wait=true || {
                log_warn "네임스페이스 삭제 실패 (계속 진행)"
            }
            log_info "네임스페이스 '${NAMESPACE}' 삭제 완료"
        else
            log_info "네임스페이스 삭제를 취소했습니다."
        fi
    else
        log_info "네임스페이스 '${NAMESPACE}'가 존재하지 않습니다."
    fi
}

# 클러스터 중지
stop_cluster() {
    log_step "클러스터 중지 옵션"
    
    if ! k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
        log_info "클러스터 '${CLUSTER_NAME}'가 존재하지 않습니다."
        return 0
    fi
    
    echo ""
    echo "다음 중 선택하세요:"
    echo "1) 클러스터 중지 (나중에 다시 시작 가능)"
    echo "2) 클러스터 삭제 (완전히 제거)"
    echo "3) 취소"
    read -p "선택 (1-3): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            log_info "클러스터를 중지합니다..."
            k3d cluster stop "${CLUSTER_NAME}" || {
                log_error "클러스터 중지 실패"
                exit 1
            }
            log_info "클러스터 중지 완료"
            log_info "다시 시작: k3d cluster start ${CLUSTER_NAME}"
            ;;
        2)
            read -p "정말로 클러스터를 삭제하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "클러스터를 삭제합니다..."
                k3d cluster delete "${CLUSTER_NAME}" || {
                    log_error "클러스터 삭제 실패"
                    exit 1
                }
                log_info "클러스터 삭제 완료"
            else
                log_info "클러스터 삭제를 취소했습니다."
            fi
            ;;
        3)
            log_info "취소했습니다."
            ;;
        *)
            log_warn "잘못된 선택입니다. 취소합니다."
            ;;
    esac
}

# 메인 함수
main() {
    log_info "=== 로컬 k3d 환경 중지 ==="
    
    uninstall_helm_releases
    delete_namespace
    stop_cluster
    
    log_info ""
    log_info "=== 환경 중지 완료 ==="
}

# 스크립트 실행
main "$@"

