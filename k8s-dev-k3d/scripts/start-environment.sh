#!/bin/bash

# 로컬 k3d 환경 시작 스크립트
# 
# 이 스크립트는 다음을 수행합니다:
# 1. k3d 클러스터 시작 (이미 존재하는 경우)
# 2. Helm 베이스 차트 배포
# 3. 서비스 헬스체크

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
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600}" # 10분

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
    
    for tool in k3d kubectl helm docker; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "다음 도구들이 설치되어 있지 않습니다: ${missing_tools[*]}"
        log_info "k3d 설치: ${K3D_DIR}/install-k3s.sh 실행"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker 데몬이 실행 중이지 않습니다."
        exit 1
    fi
    
    log_info "필수 도구 확인 완료"
}

# k3d 클러스터 시작
start_cluster() {
    log_step "k3d 클러스터 확인 중..."
    
    # kubeconfig 디렉토리 생성
    mkdir -p "$(dirname "${KUBECONFIG_FILE}")"
    
    # 클러스터 존재 확인
    if ! k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
        log_warn "클러스터 '${CLUSTER_NAME}'가 존재하지 않습니다."
        log_info "클러스터를 생성합니다..."
        "${K3D_DIR}/install-k3s.sh"
    else
        # 클러스터가 중지된 경우 시작
        log_info "클러스터 상태 확인 중..."
        
        # kubeconfig를 먼저 가져와서 연결 테스트
        k3d kubeconfig write "${CLUSTER_NAME}" --output "${KUBECONFIG_FILE}" || {
            log_error "kubeconfig 가져오기에 실패했습니다."
            exit 1
        }
        
        export KUBECONFIG="${KUBECONFIG_FILE}"
        
        # kubectl로 클러스터 상태 확인
        if ! kubectl cluster-info &> /dev/null; then
            log_info "클러스터가 중지된 것으로 보입니다. 시작합니다..."
            k3d cluster start "${CLUSTER_NAME}" || {
                log_error "클러스터 시작에 실패했습니다."
                exit 1
            }
            
            # 클러스터 시작 후 kubeconfig 다시 가져오기
            log_info "kubeconfig 업데이트 중..."
            k3d kubeconfig write "${CLUSTER_NAME}" --output "${KUBECONFIG_FILE}" || {
                log_error "kubeconfig 업데이트에 실패했습니다."
                exit 1
            }
            export KUBECONFIG="${KUBECONFIG_FILE}"
        else
            log_info "클러스터가 이미 실행 중입니다."
        fi
    fi
    
    # KUBECONFIG 환경 변수 설정 (이미 설정되어 있을 수 있음)
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    # 클러스터 연결 확인 (재시도 로직 추가)
    log_info "클러스터 연결 확인 중..."
    local retry_count=0
    local max_retries=5
    while [ $retry_count -lt $max_retries ]; do
        if kubectl cluster-info &> /dev/null; then
            log_info "클러스터 연결 성공"
            break
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_warn "클러스터 연결 실패, 재시도 중... ($retry_count/$max_retries)"
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        log_error "클러스터에 연결할 수 없습니다."
        log_info "kubeconfig 파일 확인: ${KUBECONFIG_FILE}"
        log_info "수동으로 kubeconfig 업데이트: k3d kubeconfig write ${CLUSTER_NAME} --output ${KUBECONFIG_FILE}"
        exit 1
    fi
    
    log_info "클러스터 준비 완료"
}

# 네임스페이스 생성
create_namespace() {
    log_step "네임스페이스 생성 중..."
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        log_info "네임스페이스 '${NAMESPACE}'가 이미 존재합니다."
    else
        kubectl create namespace "${NAMESPACE}"
        log_info "네임스페이스 '${NAMESPACE}' 생성 완료"
    fi
}

# 프로젝트 루트 찾기
find_project_root() {
    local current_dir="${SCRIPT_DIR}"
    while [ "${current_dir}" != "/" ]; do
        if [ -d "${current_dir}/helm" ] && [ -d "${current_dir}/k8s-dev-k3d" ]; then
            echo "${current_dir}"
            return 0
        fi
        current_dir=$(dirname "${current_dir}")
    done
    return 1
}

# Helm 차트 배포
deploy_helm_charts() {
    log_step "Helm 차트 배포 중..."
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    # Helm 저장소 업데이트
    helm repo update
    
    # 프로젝트 루트 찾기
    local project_root
    if ! project_root=$(find_project_root); then
        log_error "프로젝트 루트를 찾을 수 없습니다. (helm 디렉토리 필요)"
        exit 1
    fi
    
    log_info "프로젝트 루트: ${project_root}"
    
    # Redis 배포 (helm/statefulset-base/redis 사용)
    local redis_chart="${project_root}/helm/statefulset-base/redis"
    local redis_values="${K3D_DIR}/values/redis.yaml"
    
    if [ -d "${redis_chart}" ]; then
        local redis_dependency_dir="${redis_chart}/charts"
        if [ ! -d "${redis_dependency_dir}" ] || [ -z "$(find "${redis_dependency_dir}" -maxdepth 1 -name '*.tgz' -print -quit 2>/dev/null)" ]; then
            log_info "Redis 차트 의존성 빌드 중..."
            if ! helm dependency build "${redis_chart}" >/dev/null 2>&1; then
                log_error "Redis 차트 의존성 빌드 실패"
                return 1
            fi
        else
            log_info "Redis 차트 의존성이 이미 준비되어 있습니다. (build 생략)"
        fi

        log_info "Redis 배포 중..."
        
        if [ -f "${redis_values}" ]; then
            helm upgrade --install redis "${redis_chart}" \
                --namespace "${NAMESPACE}" \
                --create-namespace \
                --values "${redis_values}" \
                --wait \
                --timeout "${WAIT_TIMEOUT}s" || {
                log_error "Redis 배포 실패"
                return 1
            }
        else
            log_warn "Redis values 파일을 찾을 수 없습니다: ${redis_values}"
            log_info "기본 설정으로 배포합니다."
            helm upgrade --install redis "${redis_chart}" \
                --namespace "${NAMESPACE}" \
                --create-namespace \
                --wait \
                --timeout "${WAIT_TIMEOUT}s" || {
                log_error "Redis 배포 실패"
                return 1
            }
        fi
        
        log_info "Redis 배포 완료"
    else
        log_warn "Redis 차트를 찾을 수 없습니다: ${redis_chart}"
    fi
    
    # PostgreSQL 배포 (bitnami/postgresql 차트 사용)
    local postgres_namespace="postgres"
    local postgres_values="${K3D_DIR}/values/postgresql.yaml"
    
    # postgres 네임스페이스 생성
    if kubectl get namespace "${postgres_namespace}" &> /dev/null; then
        log_info "네임스페이스 '${postgres_namespace}'가 이미 존재합니다."
    else
        kubectl create namespace "${postgres_namespace}"
        log_info "네임스페이스 '${postgres_namespace}' 생성 완료"
    fi
    
    # Bitnami 저장소 확인 및 추가
    if ! helm repo list | grep -q "^bitnami"; then
        log_info "Bitnami Helm 저장소 추가 중..."
        helm repo add bitnami https://charts.bitnami.com/bitnami || {
            log_error "Bitnami 저장소 추가 실패"
            return 1
        }
    fi
    
    log_info "Helm 저장소 업데이트 중..."
    helm repo update
    
    log_info "PostgreSQL 배포 중..."
    
    if [ -f "${postgres_values}" ]; then
        helm upgrade --install pg bitnami/postgresql \
            --namespace "${postgres_namespace}" \
            --create-namespace \
            --values "${postgres_values}" \
            --wait \
            --timeout "${WAIT_TIMEOUT}s" || {
            log_error "PostgreSQL 배포 실패"
            return 1
        }
    else
        log_warn "PostgreSQL values 파일을 찾을 수 없습니다: ${postgres_values}"
        log_info "기본 설정으로 배포합니다."
        helm upgrade --install pg bitnami/postgresql \
            --namespace "${postgres_namespace}" \
            --create-namespace \
            --wait \
            --timeout "${WAIT_TIMEOUT}s" || {
            log_error "PostgreSQL 배포 실패"
            return 1
        }
    fi
    
    log_info "PostgreSQL 배포 완료"
}

# 헬스체크
health_check() {
    log_step "헬스체크 수행 중..."
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    # Pod 상태 확인
    local pods_not_ready
    pods_not_ready=$(kubectl get pods -n "${NAMESPACE}" \
        --field-selector=status.phase!=Running,status.phase!=Succeeded \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "${pods_not_ready}" -gt 0 ]; then
        log_warn "일부 Pod가 준비되지 않았습니다."
        kubectl get pods -n "${NAMESPACE}"
    else
        log_info "모든 Pod가 정상 상태입니다."
    fi
    
    # 서비스 확인
    log_info "서비스 목록:"
    kubectl get svc -n "${NAMESPACE}" || true
}

# 상태 출력
show_status() {
    log_step "환경 상태:"
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    echo ""
    echo "=== 클러스터 정보 ==="
    kubectl cluster-info | head -n 1
    
    echo ""
    echo "=== 노드 상태 ==="
    kubectl get nodes
    
    echo ""
    echo "=== 네임스페이스 ==="
    kubectl get namespace "${NAMESPACE}" || true
    
    echo ""
    echo "=== Pod 상태 ==="
    kubectl get pods -n "${NAMESPACE}" || true
    
    echo ""
    echo "=== 서비스 ==="
    kubectl get svc -n "${NAMESPACE}" || true
    
    echo ""
    echo "=== PVC 상태 ==="
    kubectl get pvc -n "${NAMESPACE}" || true
    
    echo ""
    log_info "kubeconfig: ${KUBECONFIG_FILE}"
    log_info "네임스페이스: ${NAMESPACE}"
}

# 메인 함수
main() {
    log_info "=== 로컬 k3d 환경 시작 ==="
    
    check_prerequisites
    start_cluster
    create_namespace
    deploy_helm_charts
    health_check
    show_status
    
    log_info ""
    log_info "=== 환경 시작 완료 ==="
    log_info ""
    log_info "다음 명령어로 환경을 사용하세요:"
    log_info "  export KUBECONFIG=${KUBECONFIG_FILE}"
    log_info "  kubectl get pods -n ${NAMESPACE}"
    log_info ""
    log_info "환경 중지: ${SCRIPT_DIR}/stop-environment.sh"
}

# 스크립트 실행
main "$@"

