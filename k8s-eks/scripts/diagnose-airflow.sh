#!/bin/bash

# Airflow 배포 진단 스크립트
# 현재 배포 상태를 확인하고 문제를 진단합니다.

set -e

# 색상 출력
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="airflow"
RELEASE_NAME="airflow"

echo -e "${BLUE}=== Airflow 배포 진단 ===${NC}\n"

# 1. Namespace 확인
echo -e "${YELLOW}[1] Namespace 확인${NC}"
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Namespace '${NAMESPACE}' 존재${NC}"
else
    echo -e "${RED}✗ Namespace '${NAMESPACE}' 없음${NC}"
    exit 1
fi

# 2. Helm 릴리스 확인
echo -e "\n${YELLOW}[2] Helm 릴리스 확인${NC}"
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    echo -e "${GREEN}✓ Helm 릴리스 '${RELEASE_NAME}' 존재${NC}"
    helm list -n "$NAMESPACE" | grep "$RELEASE_NAME"
else
    echo -e "${RED}✗ Helm 릴리스 '${RELEASE_NAME}' 없음${NC}"
fi

# 3. Pod 상태 확인
echo -e "\n${YELLOW}[3] Pod 상태 확인${NC}"
PODS=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -z "$PODS" ]; then
    echo -e "${RED}✗ Pod가 없습니다${NC}"
else
    kubectl get pods -n "$NAMESPACE"
    echo ""
    
    # 각 Pod의 상세 상태 확인
    for pod in $PODS; do
        STATUS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        READY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null || echo "false")
        
        if [ "$STATUS" != "Running" ] || [[ "$READY" == *"false"* ]]; then
            echo -e "${RED}⚠ Pod '${pod}' 문제 발견${NC}"
            echo -e "${YELLOW}상태: ${STATUS}${NC}"
            echo -e "${YELLOW}이벤트:${NC}"
            kubectl get events --field-selector involvedObject.name="$pod" -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -5
            echo ""
        fi
    done
fi

# 4. PVC 상태 확인
echo -e "${YELLOW}[4] PVC 상태 확인${NC}"
PVCs=$(kubectl get pvc -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -z "$PVCs" ]; then
    echo -e "${YELLOW}⚠ PVC가 없습니다${NC}"
else
    kubectl get pvc -n "$NAMESPACE"
    echo ""
    
    for pvc in $PVCs; do
        STATUS=$(kubectl get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" != "Bound" ]; then
            echo -e "${RED}⚠ PVC '${pvc}' 바인딩되지 않음 (상태: ${STATUS})${NC}"
            echo -e "${YELLOW}상세 정보:${NC}"
            kubectl describe pvc "$pvc" -n "$NAMESPACE" | grep -A 10 "Events:" || true
            echo ""
        fi
    done
fi

# 5. 서비스 확인
echo -e "${YELLOW}[5] 서비스 확인${NC}"
kubectl get svc -n "$NAMESPACE"
echo ""

# 6. StorageClass 확인
echo -e "${YELLOW}[6] StorageClass 확인${NC}"
DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
if [ -z "$DEFAULT_SC" ]; then
    echo -e "${RED}✗ 기본 StorageClass가 설정되어 있지 않습니다${NC}"
    echo -e "${YELLOW}사용 가능한 StorageClass:${NC}"
    kubectl get storageclass
else
    echo -e "${GREEN}✓ 기본 StorageClass: ${DEFAULT_SC}${NC}"
fi

# 7. 최근 이벤트 확인
echo -e "\n${YELLOW}[7] 최근 이벤트 (최근 10개)${NC}"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10

# 8. 문제가 있는 Pod의 로그 확인
echo -e "\n${YELLOW}[8] 문제가 있는 Pod 로그 (최근 20줄)${NC}"
for pod in $PODS; do
    STATUS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$STATUS" != "Running" ]; then
        echo -e "${RED}Pod: ${pod}${NC}"
        kubectl logs "$pod" -n "$NAMESPACE" --tail=20 2>&1 || true
        echo ""
    fi
done

# 9. 요약
echo -e "\n${BLUE}=== 진단 요약 ===${NC}"
TOTAL_PODS=$(echo "$PODS" | wc -w | tr -d ' ')
RUNNING_PODS=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | wc -w | tr -d ' ')

if [ "$TOTAL_PODS" -gt 0 ]; then
    echo -e "총 Pod: ${TOTAL_PODS}"
    echo -e "실행 중: ${RUNNING_PODS}"
    if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ]; then
        echo -e "${GREEN}✓ 모든 Pod가 정상 실행 중입니다${NC}"
    else
        echo -e "${RED}✗ 일부 Pod에 문제가 있습니다${NC}"
    fi
fi

echo -e "\n${YELLOW}추가 진단 명령어:${NC}"
echo -e "  - 특정 Pod 로그: kubectl logs <pod-name> -n ${NAMESPACE}"
echo -e "  - Pod 상세 정보: kubectl describe pod <pod-name> -n ${NAMESPACE}"
echo -e "  - 모든 리소스: kubectl get all -n ${NAMESPACE}"


