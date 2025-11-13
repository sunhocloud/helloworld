#!/bin/bash

# k3d 클러스터 및 리소스 정리 스크립트

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 변수
CLUSTER_NAME="${CLUSTER_NAME:-msa-quality-cluster}"

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

# k3d 클러스터 삭제
delete_clusters() {
    log_step "k3d 클러스터 확인 및 삭제 중..."
    
    local clusters
    clusters=$(k3d cluster list 2>/dev/null | grep -v "^NAME" | awk '{print $1}' || echo "")
    
    if [ -z "$clusters" ]; then
        log_info "삭제할 k3d 클러스터가 없습니다."
        return 0
    fi
    
    log_info "다음 클러스터를 발견했습니다:"
    echo "$clusters"
    
    read -p "모든 클러스터를 삭제하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "클러스터 삭제를 취소했습니다."
        return 0
    fi
    
    while IFS= read -r cluster; do
        if [ -n "$cluster" ]; then
            log_info "클러스터 '${cluster}' 삭제 중..."
            k3d cluster delete "$cluster" || {
                log_warn "클러스터 '${cluster}' 삭제 실패 (계속 진행)"
            }
        fi
    done <<< "$clusters"
    
    log_info "클러스터 삭제 완료"
}

# Docker 컨테이너 정리
cleanup_containers() {
    log_step "k3d 관련 Docker 컨테이너 정리 중..."
    
    local containers
    containers=$(docker ps -a --format '{{.Names}}' | grep -E "k3d-.*" || true)
    
    if [ -z "$containers" ]; then
        log_info "정리할 k3d 컨테이너가 없습니다."
        return 0
    fi
    
    log_info "다음 컨테이너를 발견했습니다:"
    echo "$containers"
    
    read -p "모든 k3d 컨테이너를 삭제하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "컨테이너 삭제를 취소했습니다."
        return 0
    fi
    
    echo "$containers" | while read -r container; do
        if [ -n "$container" ]; then
            log_info "컨테이너 '${container}' 삭제 중..."
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
    
    log_info "컨테이너 정리 완료"
}

# Docker 네트워크 정리
cleanup_networks() {
    log_step "k3d 관련 Docker 네트워크 정리 중..."
    
    local networks
    networks=$(docker network ls --format '{{.Name}}' | grep -E "k3d-.*" || true)
    
    if [ -z "$networks" ]; then
        log_info "정리할 k3d 네트워크가 없습니다."
        return 0
    fi
    
    log_info "다음 네트워크를 발견했습니다:"
    echo "$networks"
    
    read -p "모든 k3d 네트워크를 삭제하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "네트워크 삭제를 취소했습니다."
        return 0
    fi
    
    echo "$networks" | while read -r network; do
        if [ -n "$network" ]; then
            log_info "네트워크 '${network}' 삭제 중..."
            docker network rm "$network" 2>/dev/null || true
        fi
    done
    
    log_info "네트워크 정리 완료"
}

# 포트 사용 확인
check_ports() {
    log_step "주요 포트 사용 확인 중..."
    
    local ports=(80 443 6443)
    local used_ports=()
    
    for port in "${ports[@]}"; do
        if command -v lsof &> /dev/null; then
            if lsof -i :"${port}" &> /dev/null; then
                used_ports+=("$port")
                log_warn "포트 ${port} 사용 중:"
                lsof -i :"${port}" | head -n 3 || true
            fi
        fi
    done
    
    if [ ${#used_ports[@]} -eq 0 ]; then
        log_info "주요 포트가 사용 가능합니다."
    else
        log_warn "다음 포트가 사용 중입니다: ${used_ports[*]}"
    fi
}

# 전체 정리
full_cleanup() {
    log_info "=== k3d 리소스 전체 정리 ==="
    
    delete_clusters
    sleep 2
    cleanup_containers
    cleanup_networks
    check_ports
    
    log_info ""
    log_info "=== 정리 완료 ==="
    log_info ""
    log_info "이제 ./install-k3s.sh를 실행할 수 있습니다."
}

# 메인 함수
main() {
    if [ "${1:-}" == "--force" ]; then
        # 강제 정리 (확인 없이)
        log_info "강제 정리 모드"
        k3d cluster delete --all 2>/dev/null || true
        
        # Docker 컨테이너 정리 (macOS 호환)
        local containers
        containers=$(docker ps -a --format '{{.Names}}' | grep -E "k3d-.*" || true)
        if [ -n "$containers" ]; then
            echo "$containers" | while read -r container; do
                [ -n "$container" ] && docker rm -f "$container" 2>/dev/null || true
            done
        fi
        
        # Docker 네트워크 정리 (macOS 호환)
        local networks
        networks=$(docker network ls --format '{{.Name}}' | grep -E "k3d-.*" || true)
        if [ -n "$networks" ]; then
            echo "$networks" | while read -r network; do
                [ -n "$network" ] && docker network rm "$network" 2>/dev/null || true
            done
        fi
        
        log_info "강제 정리 완료"
    else
        full_cleanup
    fi
}

# 스크립트 실행
main "$@"

