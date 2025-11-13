#!/bin/bash

# EKS에 Airflow 배포 스크립트
# NetApp 문서 기반 배포

set -e

# 색상 출력
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 스크립트 디렉토리 찾기
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALUES_FILE="${SCRIPT_DIR}/../values/airflow.yaml"
HELM_CHART="${PROJECT_ROOT}/helm/management-base/airflow"
NAMESPACE="airflow"
RELEASE_NAME="airflow"

echo -e "${GREEN}=== EKS Airflow 배포 스크립트 ===${NC}"

# 1. 필수 도구 확인
echo -e "\n${YELLOW}[1/6] 필수 도구 확인${NC}"
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl이 설치되어 있지 않습니다.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm이 설치되어 있지 않습니다.${NC}" >&2; exit 1; }

# 2. Kubernetes 연결 확인
echo -e "\n${YELLOW}[2/6] Kubernetes 클러스터 연결 확인${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Kubernetes 클러스터에 연결할 수 없습니다.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Kubernetes 클러스터 연결 확인${NC}"

# 3. 기본 StorageClass 확인
echo -e "\n${YELLOW}[3/6] 기본 StorageClass 확인${NC}"
DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
if [ -z "$DEFAULT_SC" ]; then
    echo -e "${YELLOW}⚠ 기본 StorageClass가 설정되어 있지 않습니다.${NC}"
    echo -e "\n${YELLOW}사용 가능한 StorageClass 목록:${NC}"
    kubectl get storageclass
    
    AVAILABLE_SCS=$(kubectl get storageclass -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    if [ -z "$AVAILABLE_SCS" ]; then
        echo -e "${RED}✗ 사용 가능한 StorageClass가 없습니다.${NC}"
        echo -e "${RED}StorageClass를 먼저 생성하거나 기본 StorageClass를 설정해야 합니다.${NC}"
        exit 1
    fi
    
    echo -e "\n${YELLOW}기본 StorageClass를 설정하시겠습니까? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        while true; do
            echo -e "${YELLOW}사용할 StorageClass 이름을 입력하세요 (위 목록에서 선택):${NC}"
            read -r sc_name
            
            # 빈 입력 체크
            if [ -z "$sc_name" ]; then
                echo -e "${RED}✗ StorageClass 이름을 입력해주세요.${NC}"
                continue
            fi
            
            # StorageClass 존재 여부 확인
            if kubectl get storageclass "$sc_name" >/dev/null 2>&1; then
                # 기존 기본 StorageClass가 있다면 제거
                if [ -n "$DEFAULT_SC" ]; then
                    kubectl patch storageclass "$DEFAULT_SC" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true
                fi
                
                # 새 StorageClass를 기본으로 설정
                if kubectl patch storageclass "$sc_name" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null; then
                    echo -e "${GREEN}✓ 기본 StorageClass 설정 완료: ${sc_name}${NC}"
                    DEFAULT_SC="$sc_name"
                    break
                else
                    echo -e "${RED}✗ StorageClass 설정에 실패했습니다. 다시 시도해주세요.${NC}"
                fi
            else
                echo -e "${RED}✗ StorageClass '${sc_name}'를 찾을 수 없습니다.${NC}"
                echo -e "${YELLOW}다시 시도하시겠습니까? (y/n)${NC}"
                read -r retry
                if [[ ! "$retry" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    echo -e "${RED}기본 StorageClass 설정이 취소되었습니다. 배포를 중단합니다.${NC}"
                    exit 1
                fi
            fi
        done
    else
        echo -e "${RED}기본 StorageClass가 필요합니다. 배포를 중단합니다.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ 기본 StorageClass: ${DEFAULT_SC}${NC}"
fi

# 4. Helm 차트 의존성 빌드
echo -e "\n${YELLOW}[4/6] Helm 차트 의존성 빌드${NC}"
if [ ! -d "$HELM_CHART" ]; then
    echo -e "${RED}Helm 차트를 찾을 수 없습니다: ${HELM_CHART}${NC}"
    exit 1
fi
cd "$HELM_CHART"
helm dependency update
echo -e "${GREEN}✓ 의존성 빌드 완료${NC}"

# 5. Namespace 생성
echo -e "\n${YELLOW}[5/6] Namespace 생성${NC}"
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Namespace '${NAMESPACE}'가 이미 존재합니다.${NC}"
else
    kubectl create namespace "$NAMESPACE"
    echo -e "${GREEN}✓ Namespace '${NAMESPACE}' 생성 완료${NC}"
fi

# 6. Airflow 배포
echo -e "\n${YELLOW}[6/6] Airflow 배포${NC}"
if [ ! -f "$VALUES_FILE" ]; then
    echo -e "${RED}Values 파일을 찾을 수 없습니다: ${VALUES_FILE}${NC}"
    exit 1
fi

# 기존 배포 확인
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    echo -e "${YELLOW}⚠ 기존 배포가 발견되었습니다. 업그레이드를 시도합니다.${NC}"
    
    # 업그레이드 시도
    if helm upgrade "$RELEASE_NAME" "$HELM_CHART" \
        -n "$NAMESPACE" \
        -f "$VALUES_FILE" \
        --wait \
        --timeout 10m 2>&1 | tee /tmp/helm-upgrade.log; then
        echo -e "${GREEN}✓ 업그레이드 성공${NC}"
    else
        UPGRADE_ERROR=$(cat /tmp/helm-upgrade.log)
        
        # StatefulSet 업데이트 오류인지 확인
        if echo "$UPGRADE_ERROR" | grep -q "StatefulSet.*is invalid.*Forbidden"; then
            echo -e "${YELLOW}⚠ StatefulSet 업데이트 제한으로 인해 재설치가 필요합니다.${NC}"
            echo -e "${YELLOW}기존 배포를 삭제하고 재설치하시겠습니까? (y/n)${NC}"
            read -r reinstall_response
            if [[ "$reinstall_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                echo -e "${YELLOW}기존 배포 삭제 중...${NC}"
                helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
                
                # StatefulSet이 남아있을 수 있으므로 강제 삭제
                echo -e "${YELLOW}남은 StatefulSet 정리 중...${NC}"
                kubectl delete statefulset -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" --ignore-not-found=true || true
                
                # PVC는 유지 (데이터 보존)
                echo -e "${YELLOW}PVC는 유지됩니다 (데이터 보존).${NC}"
                
                echo -e "${YELLOW}재설치 진행 중...${NC}"
                helm install "$RELEASE_NAME" "$HELM_CHART" \
                    -n "$NAMESPACE" \
                    -f "$VALUES_FILE" \
                    --wait \
                    --timeout 10m
            else
                echo -e "${RED}업그레이드가 취소되었습니다.${NC}"
                exit 1
            fi
        else
            echo -e "${RED}✗ 업그레이드 실패${NC}"
            echo -e "${RED}오류 내용:${NC}"
            echo "$UPGRADE_ERROR"
            exit 1
        fi
    fi
else
    helm install "$RELEASE_NAME" "$HELM_CHART" \
        -n "$NAMESPACE" \
        -f "$VALUES_FILE" \
        --wait \
        --timeout 10m
fi

echo -e "\n${GREEN}=== 배포 완료! ===${NC}"

# 7. 배포 상태 확인
echo -e "\n${YELLOW}Pod 상태 확인 중...${NC}"
kubectl get pods -n "$NAMESPACE" -w &
KUBECTL_PID=$!
sleep 10
kill $KUBECTL_PID 2>/dev/null || true

echo -e "\n${GREEN}Pod 목록:${NC}"
kubectl get pods -n "$NAMESPACE"

# 8. 서비스 URL 출력
echo -e "\n${GREEN}=== Airflow 접속 정보 ===${NC}"
NODE_PORT=$(kubectl get --namespace "$NAMESPACE" -o jsonpath="{.spec.ports[0].nodePort}" services "${RELEASE_NAME}-web" 2>/dev/null || echo "")
if [ -n "$NODE_PORT" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='ExternalIP')].address}" 2>/dev/null)
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='InternalIP')].address}" 2>/dev/null)
    fi
    if [ -n "$NODE_IP" ] && [ -n "$NODE_PORT" ]; then
        echo -e "${GREEN}Airflow Web UI: http://${NODE_IP}:${NODE_PORT}${NC}"
    fi
fi

echo -e "\n${YELLOW}기본 로그인 정보:${NC}"
echo -e "Username: admin"
echo -e "Password: admin"
echo -e "\n${YELLOW}※ 보안을 위해 초기 배포 후 비밀번호를 변경하세요.${NC}"

echo -e "\n${GREEN}배포 완료!${NC}"

