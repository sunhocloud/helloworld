# MSA 서비스와 Istio Gateway 연동 가이드

## 📋 개요

MSA 서비스들을 Istio Gateway와 연동하는 방법입니다. 이미 HTTPRoute가 설정되어 있으므로, 서비스를 올바르게 배포하기만 하면 자동으로 연동됩니다.

## 🔗 연동 구조

```
외부 요청
    ↓
[Istio Gateway (NLB)]
    ↓
[HTTPRoute] → 경로 기반 라우팅
    ↓
[Kubernetes Service]
    ↓
[Pod (Istio Sidecar 자동 주입)]
    ↓
[mTLS 암호화된 서비스 간 통신]
```

## 🚀 서비스 배포 방법

### 1. 필수 조건

#### 네임스페이스
- **반드시 `ecommerce` 네임스페이스에 배포**
- Istio 자동 주입이 활성화되어 있음

```bash
# 네임스페이스 확인
kubectl get namespace ecommerce --show-labels
# istio-injection=enabled 라벨이 있어야 함
```

#### 서비스 이름과 포트
HTTPRoute의 `backendRefs`와 일치해야 합니다:

| 서비스 | HTTPRoute 파일 | 서비스 이름 | 포트 |
|--------|---------------|------------|------|
| Order Service | `04-httproute-order-service.yaml` | `order-service` | `8080` |
| Product Service | `04-httproute-product-service.yaml` | `product-service` | `8080` |
| Payment Service | `04-httproute-payment-service.yaml` | `payment-service` | `8080` |
| User Service | `04-httproute-user-service.yaml` | `user-service` | `8080` |
| Auth Service | `04-httproute-auth-service.yaml` | `auth-service` | `8080` |
| Store Service | `04-httproute-store-service.yaml` | `store-service` | `8080` |
| Review Service | `04-httproute-review-service.yaml` | `review-service` | `8080` |
| Recommendation Service | `04-httproute-recommendation-service.yaml` | `recommendation-service` | `8080` |
| Analytics Service | `04-httproute-analytics-service.yaml` | `analytics-service` | `8080` |

### 2. Helm 차트로 배포 (권장)

#### 예시: Order Service 배포

```bash
# 1. Helm 차트 디렉토리로 이동
cd helm/services/order-service  # 또는 해당 서비스 디렉토리

# 2. Dependencies 빌드
helm dependency build

# 3. ecommerce 네임스페이스에 배포
helm install order-service . \
  --namespace ecommerce \
  --create-namespace \
  --set service.name=order-service \
  --set service.port=8080 \
  --set service.targetPort=8080 \
  --wait
```

#### 서비스 이름 확인
Helm 차트의 `values.yaml`에서 서비스 이름이 올바른지 확인:

```yaml
# values.yaml
service:
  name: order-service  # HTTPRoute의 backendRefs.name과 일치해야 함
  port: 8080          # HTTPRoute의 backendRefs.port와 일치해야 함
  targetPort: 8080
```

### 3. 직접 YAML로 배포

#### Service 리소스 예시

```yaml
apiVersion: v1
kind: Service
metadata:
  name: order-service  # ⚠️ HTTPRoute의 backendRefs.name과 일치
  namespace: ecommerce  # ⚠️ 반드시 ecommerce 네임스페이스
spec:
  ports:
  - port: 8080         # ⚠️ HTTPRoute의 backendRefs.port와 일치
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: order-service
```

#### Deployment 예시

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: ecommerce  # ⚠️ 반드시 ecommerce 네임스페이스
spec:
  replicas: 1
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
      - name: order-service
        image: your-registry/order-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "prod"
```

**중요**: Pod는 자동으로 Istio Sidecar가 주입됩니다 (네임스페이스에 `istio-injection=enabled` 라벨이 있으므로).

## 🔄 연동 흐름

### 1. 외부에서 서비스 접근

```bash
# LoadBalancer 주소 확인
export GATEWAY_HOST=$(kubectl get gateway ecommerce-gateway -n ecommerce \
  -o jsonpath='{.status.addresses[0].value}')

# Order Service 호출
curl -H "Host: api.ecommerce.com" \
  "http://${GATEWAY_HOST}/api/v1/orders"

# Product Service 호출
curl -H "Host: api.ecommerce.com" \
  "http://${GATEWAY_HOST}/api/v1/products"
```

**라우팅 과정**:
1. 요청이 `api.ecommerce.com/api/v1/orders`로 들어옴
2. `ecommerce-gateway`가 요청을 받음
3. `order-service-route` HTTPRoute가 `/api/v1/orders` 경로 매칭
4. `order-service:8080`으로 트래픽 전달
5. Kubernetes Service가 Pod로 로드밸런싱
6. Istio Sidecar가 mTLS로 암호화하여 다른 서비스와 통신

### 2. 서비스 간 통신 (내부)

서비스 간 통신은 **자동으로 mTLS로 암호화**됩니다:

```java
// Order Service에서 Product Service 호출
@RestTemplate
public class OrderService {
    public Product getProduct(Long productId) {
        // 내부 서비스 이름 사용 (포트는 선택사항)
        String url = "http://product-service.ecommerce.svc.cluster.local:8080/api/v1/products/" + productId;
        return restTemplate.getForObject(url, Product.class);
    }
}
```

**통신 과정**:
1. Order Service Pod에서 `product-service` 호출
2. Istio Sidecar가 자동으로 요청을 가로챔
3. mTLS 인증서로 암호화하여 전송
4. Product Service의 Sidecar가 복호화
5. Product Service로 전달

## ✅ 배포 후 확인

### 1. 서비스 배포 확인

```bash
# Pod 확인
kubectl get pods -n ecommerce -l app=order-service

# Service 확인
kubectl get svc -n ecommerce order-service

# Endpoints 확인 (Pod가 연결되었는지)
kubectl get endpoints -n ecommerce order-service
```

### 2. Istio Sidecar 주입 확인

```bash
# Pod에 2개의 컨테이너가 있어야 함 (앱 + istio-proxy)
kubectl get pod <pod-name> -n ecommerce -o jsonpath='{.spec.containers[*].name}'
# 출력: order-service istio-proxy
```

### 3. HTTPRoute 연동 확인

```bash
# HTTPRoute 상태 확인
kubectl get httproute order-service-route -n ecommerce -o yaml

# Gateway를 통한 접근 테스트
curl -H "Host: api.ecommerce.com" \
  "http://${GATEWAY_HOST}/api/v1/orders/health"
```

### 4. mTLS 확인

```bash
# mTLS 인증서 확인
export POD_NAME=$(kubectl get pods -n ecommerce -l app=order-service -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config secret ${POD_NAME}.ecommerce

# mTLS 연결 확인
istioctl authn tls-check ${POD_NAME}.ecommerce product-service.ecommerce.svc.cluster.local
```

## 🎯 실제 배포 예시

### Order Service 전체 배포

```bash
# 1. 네임스페이스 확인
kubectl get namespace ecommerce

# 2. Helm 차트로 배포
cd helm/services/order-service
helm dependency build
helm install order-service . \
  --namespace ecommerce \
  --set service.name=order-service \
  --set service.port=8080 \
  --set image.repository=your-registry/order-service \
  --set image.tag=latest \
  --wait

# 3. 배포 확인
kubectl get pods -n ecommerce -l app=order-service
kubectl get svc -n ecommerce order-service

# 4. Gateway를 통한 접근 테스트
export GATEWAY_HOST=$(kubectl get gateway ecommerce-gateway -n ecommerce \
  -o jsonpath='{.status.addresses[0].value}')
curl -H "Host: api.ecommerce.com" \
  "http://${GATEWAY_HOST}/api/v1/orders/health"
```

## 🔧 문제 해결

### 서비스가 라우팅되지 않음

```bash
# 1. 서비스 이름 확인
kubectl get svc -n ecommerce
# 이름이 HTTPRoute의 backendRefs.name과 일치하는지 확인

# 2. 포트 확인
kubectl get svc order-service -n ecommerce -o yaml
# 포트가 HTTPRoute의 backendRefs.port와 일치하는지 확인

# 3. Endpoints 확인
kubectl get endpoints order-service -n ecommerce
# Pod가 연결되어 있는지 확인

# 4. HTTPRoute 상태 확인
kubectl describe httproute order-service-route -n ecommerce
```

### mTLS 연결 실패

```bash
# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce

# 인증서 확인
istioctl proxy-config secret <pod-name>.ecommerce
```

### 503 Service Unavailable

```bash
# Pod 상태 확인
kubectl get pods -n ecommerce -l app=order-service

# Pod 로그 확인
kubectl logs -n ecommerce -l app=order-service --tail=100

# Readiness Probe 확인
kubectl describe pod <pod-name> -n ecommerce | grep -A 5 Readiness
```

## 📝 체크리스트

서비스를 배포하기 전에 확인:

- [ ] 네임스페이스가 `ecommerce`인가?
- [ ] 서비스 이름이 HTTPRoute의 `backendRefs.name`과 일치하는가?
- [ ] 서비스 포트가 HTTPRoute의 `backendRefs.port`와 일치하는가?
- [ ] Deployment의 selector가 Service의 selector와 일치하는가?
- [ ] Pod가 정상적으로 실행 중인가?
- [ ] Istio Sidecar가 주입되었는가? (Pod에 2개의 컨테이너)
- [ ] Service의 Endpoints에 Pod가 연결되어 있는가?

## 🎓 요약

1. **서비스 배포**: `ecommerce` 네임스페이스에 배포
2. **이름/포트 일치**: HTTPRoute의 `backendRefs`와 일치
3. **자동 연동**: HTTPRoute가 이미 설정되어 있으면 자동으로 라우팅됨
4. **mTLS 자동**: 서비스 간 통신은 자동으로 mTLS 암호화
5. **외부 접근**: Gateway를 통해 `api.ecommerce.com`으로 접근

**핵심**: HTTPRoute가 이미 설정되어 있으므로, 서비스를 올바른 이름과 포트로 배포하기만 하면 자동으로 연동됩니다!

