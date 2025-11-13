#!/bin/bash

# SOPS Age 키 설정 스크립트 (로컬 k3d 환경용)
# Age 키를 생성하고 .sops.yaml에 설정합니다.

set -e

# 색상 출력
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 함수: 로그 출력
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Age 설치 확인
check_age() {
    if ! command -v age &> /dev/null; then
        log_error "Age가 설치되어 있지 않습니다."
        log_info "다음 명령으로 설치하세요:"
        echo "  macOS: brew install age"
        echo "  Linux: curl -LO https://github.com/FiloSottile/age/releases/latest/download/age-v1.1.1-linux-amd64.tar.gz && tar -xzf age-v1.1.1-linux-amd64.tar.gz && sudo mv age/age /usr/local/bin/"
        exit 1
    fi
    log_info "Age가 설치되어 있습니다: $(age --version)"
}

# SOPS 설치 확인
check_sops() {
    if ! command -v sops &> /dev/null; then
        log_error "SOPS가 설치되어 있지 않습니다."
        log_info "다음 명령으로 설치하세요:"
        echo "  macOS: brew install sops"
        echo "  Linux: curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 && sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops && chmod +x /usr/local/bin/sops"
        exit 1
    fi
    log_info "SOPS가 설치되어 있습니다: $(sops --version)"
}

# Age 키 생성
create_age_key() {
    local age_key_dir="$HOME/.config/sops/age"
    local age_key_file="$age_key_dir/keys.txt"
    
    log_info "Age 키 생성"
    
    # 디렉토리 생성
    mkdir -p "$age_key_dir"
    
    # 키가 이미 존재하는지 확인
    if [ -f "$age_key_file" ]; then
        log_warn "Age 키가 이미 존재합니다: $age_key_file"
        read -p "기존 키를 사용하시겠습니까? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "새 키를 생성합니다."
            age-keygen -o "$age_key_file"
        fi
    else
        log_info "새 Age 키 생성: $age_key_file"
        age-keygen -o "$age_key_file"
    fi
    
    # 공개 키 추출
    AGE_PUBLIC_KEY=$(grep "public key" "$age_key_file" | awk '{print $4}')
    
    if [ -z "$AGE_PUBLIC_KEY" ]; then
        log_error "공개 키를 찾을 수 없습니다."
        exit 1
    fi
    
    log_info "Age 공개 키: $AGE_PUBLIC_KEY"
    log_warn "개인 키는 안전하게 보관하세요: $age_key_file"
    
    echo "$AGE_PUBLIC_KEY"
}

# .sops.yaml 업데이트
update_sops_config() {
    local age_public_key=$1
    local sops_config_file=".sops.yaml"
    
    log_info ".sops.yaml 파일 업데이트"
    
    if [ ! -f "$sops_config_file" ]; then
        log_error ".sops.yaml 파일을 찾을 수 없습니다."
        exit 1
    fi
    
    # Age 공개 키로 교체
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/age: 'age1[^']*'/age: '$age_public_key'/" "$sops_config_file"
    else
        # Linux
        sed -i "s/age: 'age1[^']*'/age: '$age_public_key'/" "$sops_config_file"
    fi
    
    log_info ".sops.yaml 파일이 업데이트되었습니다."
}

# 메인 실행
main() {
    log_info "SOPS Age 키 설정 시작"
    
    # 현재 디렉토리 확인
    if [ ! -f ".sops.yaml" ]; then
        log_error "프로젝트 루트에서 실행해주세요 (.sops.yaml 파일이 있는 디렉토리)"
        exit 1
    fi
    
    check_age
    check_sops
    
    # Age 키 생성
    AGE_PUBLIC_KEY=$(create_age_key)
    
    # .sops.yaml 업데이트
    update_sops_config "$AGE_PUBLIC_KEY"
    
    log_info "설정 완료!"
    log_info "다음 단계:"
    echo "1. k8s-dev-k3d/values/ 디렉토리에서 시크릿 파일 생성"
    echo "2. 시크릿 파일 암호화: sops -e postgresql.secrets.yaml > postgresql.secrets.enc.yaml"
    echo "3. Helm 배포 시 암호화된 파일 사용"
}

# 실행
main "$@"

