#!/bin/bash

# Airflow 재설치 스크립트
# StatefulSet 업데이트 오류 시 사용

set -e

# 색상 출력
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALUES_FILE="${SCRIPT_DIR}/../values/airflow.yaml"
HELM_CHART="${PROJECT_ROOT}/helm/management-base/airflow"
NAMESPACE="airflow"
RELEASE_NAME="airflow"

echo -e "${YELLOW}=== Airflow 재설치 스크립트 ===${NC}"
echo -e "${YELLOW}⚠ 주의: 이 스크립트는 기존 배포를 삭제하고 재설치합니다.${NC}"
echo -e "${YELLOW}PVC는 유지되므로 데이터는 보존됩니다.${NC}"
echo -e "\n계속하시겠습니까? (y/n)"
read -r confirm
if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${RED}취소되었습니다.${NC}"
    exit 0
fi

# 1. Helm 릴리스 삭제
echo -e "\n${YELLOW}[1/4] Helm 릴리스 삭제${NC}"
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
    echo -e "${GREEN}✓ Helm 릴리스 삭제 완료${NC}"
else
    echo -e "${YELLOW}⚠ Helm 릴리스가 없습니다.${NC}"
fi

# 2. StatefulSet 강제 삭제
echo -e "\n${YELLOW}[2/4] StatefulSet 정리${NC}"
kubectl delete statefulset -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME" --ignore-not-found=true || true
kubectl delete statefulset -n "$NAMESPACE" airflow-redis airflow-worker airflow-postgresql --ignore-not-found=true || true
echo -e "${GREEN}✓ StatefulSet 정리 완료${NC}"

# 3. PVC는 유지 (데이터 보존)
echo -e "\n${YELLOW}[3/4] PVC 확인${NC}"
PVC_COUNT=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$PVC_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ PVC ${PVC_COUNT}개가 유지됩니다 (데이터 보존)${NC}"
    kubectl get pvc -n "$NAMESPACE"
else
    echo -e "${YELLOW}⚠ PVC가 없습니다.${NC}"
fi

# 4. 재설치
echo -e "\n${YELLOW}[4/4] Airflow 재설치${NC}"
if [ ! -f "$VALUES_FILE" ]; then
    echo -e "${RED}Values 파일을 찾을 수 없습니다: ${VALUES_FILE}${NC}"
    exit 1
fi

if [ ! -d "$HELM_CHART" ]; then
    echo -e "${RED}Helm 차트를 찾을 수 없습니다: ${HELM_CHART}${NC}"
    exit 1
fi

cd "$HELM_CHART"
helm dependency update
cd "$PROJECT_ROOT"

helm install "$RELEASE_NAME" "$HELM_CHART" \
    -n "$NAMESPACE" \
    -f "$VALUES_FILE" \
    --wait \
    --timeout 10m

echo -e "\n${GREEN}=== 재설치 완료! ===${NC}"

# 배포 상태 확인
echo -e "\n${YELLOW}Pod 상태 확인 중...${NC}"
sleep 5
kubectl get pods -n "$NAMESPACE"

echo -e "\n${GREEN}재설치 완료!${NC}"


