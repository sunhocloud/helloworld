# Istio 테스트 가이드 (EKS 환경)

EKS 환경에서 Istio 설치를 테스트하는 방법입니다.

## 🚀 빠른 테스트

### 자동 테스트 스크립트 실행

```bash
cd k8s-eks/istio
./test-istio.sh
```

이 스크립트는 다음을 자동으로 수행합니다:
1. Istio 설치 상태 확인
2. 테스트 애플리케이션 (httpbin) 배포
3. Gateway를 통한 트래픽 테스트
4. mTLS 확인

## 📋 수동 테스트 단계

### 1. Istio 설치 상태 확인

```bash
# Istio Control Plane 확인
kubectl get pods -n istio-system

# Ingress Gateway 확인
kubectl get pods -n istio-system -l app=istio-ingressgateway

# LoadBalancer 주소 확인
kubectl get svc -n istio-system istio-ingressgateway

# Gateway 리소스 확인
kubectl get gateway -n ecommerce

# HTTPRoute 확인
kubectl get httproute -n ecommerce
```

### 2. LoadBalancer 주소 확인

```bash
# NLB 주소 가져오기
export GATEWAY_HOST=$(kubectl get svc -n istio-system istio-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Gateway 주소: $GATEWAY_HOST"
```

**참고**: LoadBalancer가 준비되는 데 몇 분이 걸릴 수 있습니다.

### 3. 테스트 애플리케이션 배포

#### httpbin 배포 (간단한 HTTP 테스트 서버)

```bash
# httpbin 배포
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: ecommerce
  labels:
    app: httpbin
spec:
  ports:
  - name: http
    port: 8000
    targetPort: 80
  selector:
    app: httpbin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: ecommerce
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
      - image: kennethreitz/httpbin:latest
        imagePullPolicy: IfNotPresent
        name: httpbin
        ports:
        - containerPort: 80
EOF

# Pod 준비 대기
kubectl wait --for=condition=ready pod -l app=httpbin -n ecommerce --timeout=120s
```

#### 테스트용 HTTPRoute 생성

```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin-route
  namespace: ecommerce
spec:
  parentRefs:
    - name: ecommerce-gateway
  hostnames:
    - "api.ecommerce.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /test
      backendRefs:
        - name: httpbin
          port: 8000
          weight: 100
EOF
```

### 4. Gateway를 통한 트래픽 테스트

```bash
# Gateway 주소 확인
export GATEWAY_HOST=$(kubectl get svc -n istio-system istio-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# HTTP 요청 테스트 (Host 헤더 필수)
curl -H "Host: api.ecommerce.com" "http://${GATEWAY_HOST}/test/get"

# 다양한 엔드포인트 테스트
curl -H "Host: api.ecommerce.com" "http://${GATEWAY_HOST}/test/status/200"
curl -H "Host: api.ecommerce.com" "http://${GATEWAY_HOST}/test/headers"
curl -H "Host: api.ecommerce.com" "http://${GATEWAY_HOST}/test/ip"
```

### 5. mTLS 확인

```bash
# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce

# Pod의 mTLS 인증서 확인
export POD_NAME=$(kubectl get pods -n ecommerce -l app=httpbin -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config secret ${POD_NAME}.ecommerce

# mTLS 연결 확인
istioctl authn tls-check ${POD_NAME}.ecommerce httpbin.ecommerce.svc.cluster.local
```

### 6. 서비스 간 통신 테스트

```bash
# httpbin Pod에 접속
kubectl exec -it -n ecommerce $(kubectl get pods -n ecommerce -l app=httpbin -o jsonpath='{.items[0].metadata.name}') -- sh

# Pod 내부에서 다른 서비스 호출 테스트
# (다른 서비스가 배포되어 있다면)
curl http://order-service.ecommerce.svc.cluster.local:8080/health
```

## 🔍 상세 진단

### Gateway 상태 확인

```bash
# Gateway 상세 정보
kubectl describe gateway ecommerce-gateway -n ecommerce

# Gateway 이벤트 확인
kubectl get events -n ecommerce --sort-by='.lastTimestamp' | grep gateway
```

### HTTPRoute 상태 확인

```bash
# HTTPRoute 상세 정보
kubectl describe httproute httpbin-route -n ecommerce

# HTTPRoute 상태 확인
kubectl get httproute httpbin-route -n ecommerce -o yaml
```

### Envoy Proxy 설정 확인

```bash
# Ingress Gateway 설정 확인
export GATEWAY_POD=$(kubectl get pods -n istio-system -l app=istio-ingressgateway -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config listeners ${GATEWAY_POD}.istio-system
istioctl proxy-config routes ${GATEWAY_POD}.istio-system
istioctl proxy-config clusters ${GATEWAY_POD}.istio-system
```

### 로그 확인

```bash
# Ingress Gateway 로그
kubectl logs -n istio-system -l app=istio-ingressgateway --tail=100

# httpbin Pod 로그
kubectl logs -n ecommerce -l app=httpbin --tail=100

# Istio Control Plane 로그
kubectl logs -n istio-system -l app=istiod --tail=100
```

## 🧪 고급 테스트

### 1. Circuit Breaker 테스트

```bash
# DestinationRule 확인
kubectl get destinationrule -n ecommerce

# Circuit Breaker 설정 확인
kubectl get destinationrule order-service-dr -n ecommerce -o yaml
```

### 2. Rate Limiting 테스트

```bash
# Rate Limit ConfigMap 확인
kubectl get configmap ratelimit-config -n ecommerce -o yaml

# Rate Limit 테스트 (여러 요청 보내기)
for i in {1..10}; do
  curl -H "Host: api.ecommerce.com" "http://${GATEWAY_HOST}/test/get"
  echo "Request $i"
done
```

### 3. JWT 인증 테스트

```bash
# Public 엔드포인트 테스트 (인증 불필요)
curl -H "Host: api.ecommerce.com" "http://${GATEWAY_HOST}/api/v1/users/login"

# Protected 엔드포인트 테스트 (JWT 필요)
curl -H "Host: api.ecommerce.com" "http://${GATEWAY_HOST}/api/v1/orders"
# → 401 Unauthorized 예상

# JWT 토큰으로 테스트
export JWT_TOKEN="your-jwt-token"
curl -H "Host: api.ecommerce.com" \
     -H "Authorization: Bearer $JWT_TOKEN" \
     "http://${GATEWAY_HOST}/api/v1/orders"
```

### 4. 재시도 및 타임아웃 테스트

```bash
# VirtualService 확인
kubectl get virtualservice -n ecommerce

# 타임아웃 테스트 (느린 응답 서비스 필요)
curl -H "Host: api.ecommerce.com" "http://${GATEWAY_HOST}/test/delay/10"
```

## 🐛 문제 해결

### LoadBalancer가 생성되지 않음

```bash
# 서비스 상태 확인
kubectl describe svc istio-ingressgateway -n istio-system

# IAM 권한 확인
# EKS 노드 그룹에 ELB 권한이 있는지 확인
```

### Gateway가 트래픽을 라우팅하지 않음

```bash
# Gateway 상태 확인
kubectl get gateway ecommerce-gateway -n ecommerce -o yaml

# HTTPRoute 상태 확인
kubectl get httproute -n ecommerce -o yaml

# Envoy 설정 확인
istioctl proxy-config listeners ${GATEWAY_POD}.istio-system
```

### 503 Service Unavailable

```bash
# 백엔드 서비스 확인
kubectl get svc -n ecommerce

# Pod 상태 확인
kubectl get pods -n ecommerce

# Endpoints 확인
kubectl get endpoints -n ecommerce
```

### mTLS 연결 실패

```bash
# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce -o yaml

# 인증서 확인
istioctl proxy-config secret ${POD_NAME}.ecommerce

# mTLS 모드 확인
istioctl authn tls-check ${POD_NAME}.ecommerce
```

## 🧹 정리

### 테스트 애플리케이션 삭제

```bash
# httpbin 삭제
kubectl delete httproute httpbin-route -n ecommerce
kubectl delete deployment httpbin -n ecommerce
kubectl delete service httpbin -n ecommerce
```

### 전체 Istio 제거

```bash
cd k8s-eks/istio
REMOVE_CONTROL_PLANE=true ./uninstall-istio.sh
```

## 📚 참고 자료

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Istio 테스트 가이드](https://istio.io/latest/docs/ops/diagnostic-tools/)

