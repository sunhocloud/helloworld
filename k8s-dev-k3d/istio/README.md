# Istio 구성 가이드

이 디렉토리는 E-Commerce MSA 시스템의 Istio Service Mesh 및 Gateway 구성을 포함합니다.

## 📋 목차

1. [개요](#개요)
2. [구성 요소](#구성-요소)
3. [설치 방법](#설치-방법)
4. [리소스 구조](#리소스-구조)
5. [보안 설정](#보안-설정)
6. [트래픽 관리](#트래픽-관리)
7. [모니터링](#모니터링)
8. [문제 해결](#문제-해결)

## 개요

이 Istio 구성은 다음을 제공합니다:

- **Kubernetes Gateway API** 기반 API Gateway
- **mTLS** 자동 암호화 (서비스 간 통신)
- **JWT 인증** 및 **역할 기반 접근 제어 (RBAC)**
- **Circuit Breaker** 및 **Resilience** 패턴
- **Rate Limiting** (Redis 기반)
- **Token Blacklist** (로그아웃된 JWT 무효화)
- **Webhook Gateway** (외부 시스템용, IP Whitelist)

## 구성 요소

### 1. Istio Control Plane

- **Istiod**: Control Plane (설정 관리, mTLS 인증서 발급)
- **Istio Gateway**: Ingress Gateway (Kubernetes Gateway API 사용)

### 2. Gateway 리소스

#### Main Gateway (`ecommerce-gateway`)
- **호스트**: `api.ecommerce.com`
- **포트**: 443 (HTTPS), 80 (HTTP → HTTPS 리다이렉트)
- **용도**: 고객 및 관리자 API 요청 처리
- **인증**: JWT 기반

#### Webhook Gateway (`webhook-gateway`)
- **호스트**: `webhook.ecommerce.com`
- **포트**: 443 (HTTPS)
- **용도**: PG사, 파트너사 Webhook 수신
- **보안**: IP Whitelist 기반 접근 제어

### 3. HTTPRoute 리소스

각 마이크로서비스별 라우팅 규칙:

- `order-service-route`: `/api/v1/orders`
- `product-service-route`: `/api/v1/products`
- `payment-service-route`: `/api/v1/payments`
- `store-service-route`: `/api/v1/stores`
- `user-service-route`: `/api/v1/users`
- `auth-service-route`: `/api/v1/auth`
- `review-service-route`: `/api/v1/reviews`
- `recommendation-service-route`: `/api/v1/recommendations`
- `analytics-service-route`: `/api/v1/analytics`

### 4. 보안 리소스

- **PeerAuthentication**: Namespace 레벨 mTLS 강제
- **RequestAuthentication**: JWT 인증 설정
- **AuthorizationPolicy**: 역할 기반 접근 제어 및 IP Whitelist

### 5. Traffic Management 리소스

- **DestinationRule**: Circuit Breaker, Connection Pool, Outlier Detection
- **VirtualService**: 재시도, 타임아웃 정책

### 6. EnvoyFilter 리소스

- **Rate Limiting**: Redis 기반 요청 속도 제한
- **Token Blacklist**: 로그아웃된 JWT 검증

## 설치 방법

### 사전 요구사항

1. **k3d 클러스터** 실행 중
2. **kubectl** 설치
3. **istioctl** 설치

```bash
# istioctl 설치
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PATH:$PWD/istio-1.22.0/bin
```

### 설치 단계

1. **Istio 설치 스크립트 실행**

```bash
cd k8s-dev-k3d/istio
./install-istio.sh
```

스크립트는 다음을 수행합니다:
- Istio Control Plane 설치
- Gateway API CRD 설치
- Istio Gateway Class 설치
- E-commerce 네임스페이스 생성 및 라벨링
- 모든 Istio 구성 리소스 배포

2. **설치 확인**

```bash
# Istio Control Plane 확인
kubectl get pods -n istio-system

# Gateway 확인
kubectl get gateway -n ecommerce

# HTTPRoute 확인
kubectl get httproute -n ecommerce

# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce
```

3. **Istio 설치 검증**

```bash
istioctl verify-install
```

## 리소스 구조

```
istio/
├── install-istio.sh              # Istio 설치 스크립트
├── README.md                      # 이 파일
└── resources/                     # Istio 구성 리소스
    ├── 01-peer-authentication.yaml
    ├── 02-gateway-main.yaml
    ├── 03-gateway-webhook.yaml
    ├── 04-httproute-*.yaml        # 각 서비스별 라우팅
    ├── 05-request-authentication.yaml
    ├── 05-virtual-service-retry-timeout.yaml
    ├── 06-authorization-policy.yaml
    ├── 07-destination-rule-*.yaml  # Circuit Breaker 설정
    └── 08-envoy-filter-*.yaml      # Rate Limiting, Token Blacklist
```

## 보안 설정

### 1. mTLS (Mutual TLS)

모든 서비스 간 통신은 자동으로 mTLS로 암호화됩니다.

```yaml
# 01-peer-authentication.yaml
spec:
  mtls:
    mode: STRICT
```

### 2. JWT 인증

**Public Endpoints** (인증 불필요):
- `/api/v1/users/register`
- `/api/v1/users/login`
- `/api/v1/users/refresh-token`
- `/api/v1/auth/login`
- `/api/v1/auth/refresh`
- `/actuator/health`
- `/actuator/prometheus`

**Protected Endpoints** (JWT 필수):
- `/api/v1/*` (위 Public Endpoints 제외)

### 3. IP Whitelist (Webhook Gateway)

PG사 및 파트너사 IP만 허용:

```yaml
# 06-authorization-policy.yaml
rules:
  - from:
      - source:
          ipBlocks:
            - "203.0.113.0/24"  # PG사 IP (실제 IP로 변경 필요)
```

**⚠️ 중요**: 실제 배포 시 IP 주소를 실제 값으로 변경하세요.

## 트래픽 관리

### 1. Circuit Breaker

각 서비스별 Circuit Breaker 설정:

- **Order Service**: 5xx 에러 5회 연속 → 30초 제외
- **Product Service**: 5xx 에러 5회 연속 → 30초 제외
- **Payment Service**: 5xx 에러 3회 연속 → 60초 제외 (더 엄격)

### 2. 재시도 정책

- **일반 서비스**: 최대 3회 재시도, 타임아웃 5초
- **Payment Service**: 최대 2회 재시도, 타임아웃 10초
- **Recommendation Service**: 최대 2회 재시도, 타임아웃 3초 (빠른 응답 목표)

### 3. Rate Limiting

Redis 기반 Rate Limiting:

- **User별**: 초당 100 요청
- **IP별**: 초당 50 요청
- **Order Service**: 초당 100 요청
- **Product Service**: 초당 200 요청
- **Payment Service**: 초당 50 요청

## 모니터링

### Istio Metrics (Prometheus)

Istio는 자동으로 Envoy 프록시 메트릭을 Prometheus로 노출합니다.

**주요 Metrics**:

```promql
# Gateway 요청 수
istio_requests_total{
  destination_service="order-service.ecommerce.svc.cluster.local"
}

# Gateway 응답 시간 (P95)
histogram_quantile(0.95,
  sum(rate(istio_request_duration_milliseconds_bucket[5m])) by (le)
)

# Circuit Breaker 상태
envoy_cluster_outlier_detection_ejections_active

# mTLS 연결 수
istio_tcp_connections_opened_total{
  connection_security_policy="mutual_tls"
}
```

### Grafana 대시보드

- **Istio Mesh Dashboard**: 전체 트래픽 흐름
- **Istio Service Dashboard**: 서비스별 메트릭
- **Istio Workload Dashboard**: Pod별 메트릭

## 문제 해결

### 1. Gateway가 준비되지 않음

```bash
# Gateway 상태 확인
kubectl get gateway -n ecommerce

# Gateway 이벤트 확인
kubectl describe gateway ecommerce-gateway -n ecommerce

# Istio Gateway Pod 확인
kubectl get pods -n istio-system -l app=istio-ingressgateway
```

### 2. mTLS 연결 실패

```bash
# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce

# mTLS 상태 확인
istioctl authn tls-check <pod-name>.<namespace> <service-name>
```

### 3. JWT 인증 실패

```bash
# RequestAuthentication 확인
kubectl get requestauthentication -n ecommerce

# AuthorizationPolicy 확인
kubectl get authorizationpolicy -n ecommerce

# JWT 검증 로그 확인
kubectl logs -n istio-system -l app=istio-ingressgateway
```

### 4. Rate Limiting 동작 안 함

```bash
# EnvoyFilter 확인
kubectl get envoyfilter -n ecommerce

# Redis 연결 확인
kubectl get svc redis -n ecommerce

# Rate Limit ConfigMap 확인
kubectl get configmap ratelimit-config -n ecommerce
```

### 5. Webhook Gateway IP 차단

```bash
# AuthorizationPolicy 확인
kubectl get authorizationpolicy webhook-ip-whitelist -n ecommerce -o yaml

# 실제 요청 IP 확인 (로그)
kubectl logs -n istio-system -l app=istio-ingressgateway | grep webhook
```

## 참고 자료

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)
- [E-Commerce MSA 아키텍처 문서](../README.md)


