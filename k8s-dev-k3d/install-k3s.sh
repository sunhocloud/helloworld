#!/bin/bash

# k3d 설치 및 k3s 클러스터 부트스트랩 스크립트
# 공식 문서: https://k3d.io/
# 
# 이 스크립트는 다음을 수행합니다:
# 1. k3d 설치 확인 및 설치 (필요시)
# 2. Helm 설치 확인 및 설치 (필요시)
# 3. k3d 클러스터 생성 및 설정
# 4. kubeconfig 설정

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 변수
CLUSTER_NAME="${CLUSTER_NAME:-msa-quality-cluster}"
K3D_VERSION="${K3D_VERSION:-v5.7.0}"
HELM_VERSION="${HELM_VERSION:-v3.14.0}"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.28.5-k3s1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_DIR="${SCRIPT_DIR}/kubeconfig"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/config"

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

# k3d 설치 확인 및 설치
check_and_install_k3d() {
    if command -v k3d &> /dev/null; then
        local installed_version
        # macOS 호환: grep -P 대신 sed 사용
        installed_version=$(k3d version 2>/dev/null | sed -n 's/.*k3d version \([^,]*\).*/\1/p' | head -n 1 || echo "unknown")
        log_info "k3d가 이미 설치되어 있습니다: ${installed_version}"
        return 0
    fi

    log_info "k3d를 설치합니다..."
    
    # OS별 설치 방법
    case "$(uname -s)" in
        Darwin)
            if command -v brew &> /dev/null; then
                brew install k3d
            else
                log_error "Homebrew가 설치되어 있지 않습니다. https://brew.sh/ 에서 설치하세요."
                exit 1
            fi
            ;;
        Linux)
            # Linux용 설치 스크립트 (공식 문서 기반)
            curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
            ;;
        *)
            log_error "지원하지 않는 OS입니다: $(uname -s)"
            exit 1
            ;;
    esac

    if ! command -v k3d &> /dev/null; then
        log_error "k3d 설치에 실패했습니다."
        exit 1
    fi

    log_info "k3d 설치 완료"
}

# Helm 설치 확인 및 설치
check_and_install_helm() {
    if command -v helm &> /dev/null; then
        local installed_version
        # macOS 호환: grep -P 대신 sed 사용
        installed_version=$(helm version --short 2>/dev/null | sed -n 's/.*v\([^+]*\).*/\1/p' | head -n 1 || echo "unknown")
        log_info "Helm이 이미 설치되어 있습니다: ${installed_version}"
        return 0
    fi

    log_info "Helm을 설치합니다..."
    
    # Helm 공식 설치 스크립트 사용
    case "$(uname -s)" in
        Darwin)
            if command -v brew &> /dev/null; then
                brew install helm
            else
                log_error "Homebrew가 설치되어 있지 않습니다."
                exit 1
            fi
            ;;
        Linux)
            # Linux용 설치 스크립트 (공식 문서 기반)
            curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
            ;;
        *)
            log_error "지원하지 않는 OS입니다: $(uname -s)"
            exit 1
            ;;
    esac

    if ! command -v helm &> /dev/null; then
        log_error "Helm 설치에 실패했습니다."
        exit 1
    fi

    log_info "Helm 설치 완료"
}

# Docker 설치 확인
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되어 있지 않습니다."
        log_info "Docker 설치: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker 데몬이 실행 중이지 않습니다."
        log_info "Docker Desktop을 시작하거나 Docker 데몬을 실행하세요."
        exit 1
    fi

    log_info "Docker 확인 완료"
}

# 포트 사용 확인
check_port_available() {
    local port=$1
    if command -v lsof &> /dev/null; then
        if lsof -i :"${port}" &> /dev/null; then
            return 1  # 포트 사용 중
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -an | grep -q ":${port} "; then
            return 1  # 포트 사용 중
        fi
    fi
    return 0  # 포트 사용 가능
}

# 포트 범위 충돌 확인 및 정리
check_and_cleanup_ports() {
    log_step "포트 충돌 확인 중..."
    
    local ports_to_check=(80 443 6443)
    local conflicting_ports=()
    
    for port in "${ports_to_check[@]}"; do
        if ! check_port_available "$port"; then
            conflicting_ports+=("$port")
        fi
    done
    
    if [ ${#conflicting_ports[@]} -gt 0 ]; then
        log_warn "다음 포트가 이미 사용 중입니다: ${conflicting_ports[*]}"
        
        # k3d 관련 프로세스 확인
        local k3d_containers
        k3d_containers=$(docker ps -a --format '{{.Names}}' | grep -E "k3d-.*-serverlb|k3d-.*-server-0" || true)
        if [ -n "$k3d_containers" ]; then
            log_warn "기존 k3d 컨테이너가 발견되었습니다."
            echo "$k3d_containers"
            read -p "기존 k3d 컨테이너를 정리하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "기존 k3d 컨테이너 정리 중..."
                echo "$k3d_containers" | while read -r container; do
                    [ -n "$container" ] && docker rm -f "$container" 2>/dev/null || true
                done
                log_info "컨테이너 정리 완료"
            fi
        fi
        
        # 포트 사용 프로세스 정보 출력
        log_info "포트 사용 프로세스 정보:"
        for port in "${conflicting_ports[@]}"; do
            if command -v lsof &> /dev/null; then
                lsof -i :"${port}" 2>/dev/null | head -n 5 || true
            fi
        done
        
        read -p "계속 진행하시겠습니까? (포트 충돌이 발생할 수 있습니다) (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "사용자가 취소했습니다."
            exit 1
        fi
    else
        log_info "주요 포트 사용 가능 확인 완료"
    fi
}

# 기존 클러스터 삭제 (선택적)
delete_existing_cluster() {
    if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
        log_warn "기존 클러스터 '${CLUSTER_NAME}'를 발견했습니다."
        echo ""
        echo "다음 중 선택하세요:"
        echo "1) 기존 클러스터 삭제하고 새로 생성"
        echo "2) 정리 스크립트 실행 (모든 k3d 리소스 정리)"
        echo "3) 취소"
        read -p "선택 (1-3): " -n 1 -r
        echo
        
        case $REPLY in
            1)
                log_info "기존 클러스터를 삭제합니다..."
                k3d cluster delete "${CLUSTER_NAME}" || true
                # 클러스터 삭제 후 잔여 컨테이너 정리
                sleep 2
                local remaining_containers
                remaining_containers=$(docker ps -a --format '{{.Names}}' | grep -E "k3d-${CLUSTER_NAME}-.*" || true)
                if [ -n "$remaining_containers" ]; then
                    echo "$remaining_containers" | while read -r container; do
                        [ -n "$container" ] && docker rm -f "$container" 2>/dev/null || true
                    done
                fi
                ;;
            2)
                log_info "정리 스크립트를 실행합니다..."
                local cleanup_script="${SCRIPT_DIR}/scripts/cleanup.sh"
                if [ -f "${cleanup_script}" ]; then
                    bash "${cleanup_script}" --force
                else
                    log_warn "정리 스크립트를 찾을 수 없습니다: ${cleanup_script}"
                    log_info "수동으로 정리합니다..."
                    k3d cluster delete "${CLUSTER_NAME}" || true
                fi
                ;;
            3)
                log_info "취소했습니다."
                exit 0
                ;;
            *)
                log_warn "잘못된 선택입니다. 취소합니다."
                exit 0
                ;;
        esac
    fi
}

# k3d 클러스터 생성
create_cluster() {
    log_info "k3d 클러스터 '${CLUSTER_NAME}'를 생성합니다..."
    
    # kubeconfig 디렉토리 생성
    mkdir -p "${KUBECONFIG_DIR}"

    # 포트 매핑 설정
    # NodePort 범위를 좁게 설정하여 포트 충돌 방지
    # 또는 환경 변수로 포트 범위를 지정할 수 있도록 함
    local nodeport_start="${NODEPORT_START:-30000}"
    local nodeport_end="${NODEPORT_END:-30100}"
    
    log_info "포트 매핑 설정:"
    log_info "  - API Server: 6443"
    log_info "  - HTTP: 80"
    log_info "  - HTTPS: 443"
    log_info "  - NodePort: ${nodeport_start}-${nodeport_end}"

    # k3d 클러스터 생성
    # 참고: https://k3d.io/v5.7.0/usage/commands/k3d_cluster_create/
    # NodePort 범위를 좁게 설정하여 포트 충돌 최소화
    if ! k3d cluster create "${CLUSTER_NAME}" \
        --image "${K3S_IMAGE}" \
        --api-port 6443 \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --port "${nodeport_start}-${nodeport_end}:${nodeport_start}-${nodeport_end}@server:0" \
        --k3s-arg "--disable=traefik@server:0" \
        --wait \
        --timeout 300s; then
        
        log_error "클러스터 생성에 실패했습니다."
        log_info ""
        log_info "문제 해결 방법:"
        log_info "1. 기존 k3d 클러스터 확인: k3d cluster list"
        log_info "2. 기존 클러스터 삭제: k3d cluster delete <cluster-name>"
        log_info "3. Docker 컨테이너 확인: docker ps -a | grep k3d"
        log_info "4. 포트 사용 확인: lsof -i :<port> 또는 netstat -an | grep <port>"
        log_info "5. 포트 범위 변경: export NODEPORT_START=30100 NODEPORT_END=30200"
        exit 1
    fi

    log_info "클러스터 생성 완료"
}

# kubeconfig 설정
setup_kubeconfig() {
    log_info "kubeconfig를 설정합니다..."
    
    # k3d kubeconfig 가져오기
    k3d kubeconfig write "${CLUSTER_NAME}" --output "${KUBECONFIG_FILE}"
    
    # KUBECONFIG 환경 변수 설정 (현재 세션용)
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    log_info "kubeconfig가 ${KUBECONFIG_FILE}에 저장되었습니다."
    log_info "사용 방법: export KUBECONFIG=${KUBECONFIG_FILE}"
}

# Helm 저장소 추가
setup_helm_repos() {
    log_info "Helm 저장소를 설정합니다..."
    
    # Bitnami 저장소 (PostgreSQL, Redis 등)
    helm repo add bitnami https://charts.bitnami.com/bitnami || true
    helm repo update
    
    # Strimzi 저장소 (Kafka/MSK 호환)
    helm repo add strimzi https://strimzi.io/charts/ || true
    helm repo update
    
    log_info "Helm 저장소 설정 완료"
}

# 클러스터 상태 확인
verify_cluster() {
    log_info "클러스터 상태를 확인합니다..."
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    if kubectl cluster-info &> /dev/null; then
        log_info "클러스터 연결 성공"
        kubectl get nodes
    else
        log_error "클러스터 연결에 실패했습니다."
        exit 1
    fi
}

# 메인 함수
main() {
    log_info "=== k3d/k3s 클러스터 부트스트랩 시작 ==="
    
    check_docker
    check_and_install_k3d
    check_and_install_helm
    check_and_cleanup_ports
    delete_existing_cluster
    create_cluster
    setup_kubeconfig
    setup_helm_repos
    verify_cluster
    
    log_info "=== 부트스트랩 완료 ==="
    log_info ""
    log_info "다음 명령어로 클러스터를 사용하세요:"
    log_info "  export KUBECONFIG=${KUBECONFIG_FILE}"
    log_info "  kubectl get nodes"
    log_info ""
    log_info "클러스터 삭제: k3d cluster delete ${CLUSTER_NAME}"
}

# 스크립트 실행
main "$@"

