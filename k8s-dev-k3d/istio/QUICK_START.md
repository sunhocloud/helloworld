# Istio 빠른 시작 가이드

## 🚀 빠른 설치

### 1. 사전 요구사항 확인

```bash
# istioctl 설치 확인
istioctl version

# k3d 클러스터 실행 확인
k3d cluster list

# kubectl 연결 확인
kubectl cluster-info
```

### 2. Istio 설치

```bash
cd k8s-dev-k3d/istio
./install-istio.sh
```

### 3. 설치 확인

```bash
# Istio Control Plane 확인
kubectl get pods -n istio-system

# Gateway 확인
kubectl get gateway -n ecommerce

# HTTPRoute 확인
kubectl get httproute -n ecommerce
```

## 📝 주요 명령어

### Gateway 상태 확인

```bash
# Gateway 리소스 확인
kubectl get gateway -n ecommerce

# Gateway 상세 정보
kubectl describe gateway ecommerce-gateway -n ecommerce

# Gateway 이벤트 확인
kubectl get events -n ecommerce --field-selector involvedObject.name=ecommerce-gateway
```

### HTTPRoute 확인

```bash
# 모든 HTTPRoute 확인
kubectl get httproute -n ecommerce

# 특정 HTTPRoute 상세 정보
kubectl describe httproute order-service-route -n ecommerce
```

### 보안 정책 확인

```bash
# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce

# RequestAuthentication 확인
kubectl get requestauthentication -n ecommerce

# AuthorizationPolicy 확인
kubectl get authorizationpolicy -n ecommerce
```

### Traffic Management 확인

```bash
# DestinationRule 확인
kubectl get destinationrule -n ecommerce

# VirtualService 확인
kubectl get virtualservice -n ecommerce
```

### mTLS 상태 확인

```bash
# 특정 Pod의 mTLS 상태 확인
istioctl authn tls-check <pod-name>.ecommerce <service-name>.ecommerce.svc.cluster.local

# 네임스페이스 전체 mTLS 상태 확인
istioctl authn tls-check -n ecommerce
```

## 🔧 문제 해결

### Gateway가 Ready 상태가 아님

```bash
# Gateway 이벤트 확인
kubectl describe gateway ecommerce-gateway -n ecommerce

# Istio Gateway Pod 로그 확인
kubectl logs -n istio-system -l app=istio-ingressgateway --tail=100
```

### HTTPRoute가 연결되지 않음

```bash
# HTTPRoute 상태 확인
kubectl describe httproute order-service-route -n ecommerce

# Service 존재 확인
kubectl get svc order-service -n ecommerce
```

### JWT 인증 실패

```bash
# RequestAuthentication 확인
kubectl get requestauthentication jwt-auth -n ecommerce -o yaml

# AuthorizationPolicy 확인
kubectl get authorizationpolicy require-jwt -n ecommerce -o yaml

# Gateway 로그에서 JWT 검증 오류 확인
kubectl logs -n istio-system -l app=istio-ingressgateway | grep -i jwt
```

## 🗑️ 제거

### Istio 구성 리소스만 제거

```bash
./uninstall-istio.sh
```

### Istio Control Plane까지 완전 제거

```bash
REMOVE_CONTROL_PLANE=true ./uninstall-istio.sh
```

## 📚 추가 자료

- [상세 가이드](./README.md)
- [E-Commerce MSA 아키텍처 문서](../../README.md)


