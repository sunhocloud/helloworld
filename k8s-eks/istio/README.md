# Istio 구성 가이드 (EKS 환경)

이 디렉토리는 E-Commerce MSA 시스템의 Istio Service Mesh 및 Gateway 구성을 EKS 환경에서 사용하기 위한 설정을 포함합니다.

## 📋 목차

1. [개요](#개요)
2. [사전 요구사항](#사전-요구사항)
3. [설치 방법](#설치-방법)
4. [EKS 환경 특화 설정](#eks-환경-특화-설정)
5. [리소스 구조](#리소스-구조)
6. [보안 설정](#보안-설정)
7. [트래픽 관리](#트래픽-관리)
8. [모니터링](#모니터링)
9. [문제 해결](#문제-해결)

## 개요

이 Istio 구성은 EKS 환경에서 다음을 제공합니다:

- **Kubernetes Gateway API** 기반 API Gateway
- **AWS Network Load Balancer (NLB)** 자동 생성
- **mTLS** 자동 암호화 (서비스 간 통신)
- **JWT 인증** 및 **역할 기반 접근 제어 (RBAC)**
- **Circuit Breaker** 및 **Resilience** 패턴
- **Rate Limiting** (Redis 기반)
- **Token Blacklist** (로그아웃된 JWT 무효화)
- **Webhook Gateway** (외부 시스템용, IP Whitelist)

## 사전 요구사항

### 1. EKS 클러스터

- EKS 클러스터가 생성되어 있어야 합니다
- `kubectl`이 EKS 클러스터에 연결되어 있어야 합니다

```bash
# EKS 클러스터 연결 확인
kubectl cluster-info

# 연결되지 않은 경우
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

### 2. 필수 도구

- **kubectl**: Kubernetes 클라이언트
- **istioctl**: Istio CLI 도구

```bash
# istioctl 설치
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PATH:$PWD/istio-1.22.0/bin

# 또는 Homebrew (macOS)
brew install istioctl
```

### 3. IAM 권한

EKS 클러스터에 다음 권한이 필요합니다:

- LoadBalancer 서비스 생성 권한
- AWS Load Balancer Controller 권한 (선택사항, ALB 사용 시)

### 4. 네임스페이스

설치 스크립트가 자동으로 `ecommerce` 네임스페이스를 생성합니다. 다른 네임스페이스를 사용하려면 환경 변수를 설정하세요:

```bash
export NAMESPACE=your-namespace
```

## 설치 방법

### 1. Istio 설치 스크립트 실행

```bash
cd k8s-eks/istio
./install-istio.sh
```

스크립트는 다음을 수행합니다:

1. **필수 도구 확인**: kubectl, istioctl 확인
2. **EKS 클러스터 연결 확인**: kubectl cluster-info 확인
3. **Istio Control Plane 설치**: 
   - Istio Operator 설치
   - LoadBalancer 타입으로 Ingress Gateway 설정 (AWS NLB 자동 생성)
4. **Gateway API CRD 설치**: Kubernetes Gateway API 설치
5. **Istio Gateway Class 설치**: Istio Gateway Class 생성
6. **네임스페이스 설정**: ecommerce 네임스페이스 생성 및 Istio 자동 주입 활성화
7. **Istio 구성 리소스 배포**: 모든 Gateway, HTTPRoute, 보안 정책 등 배포

### 2. 설치 확인

```bash
# Istio Control Plane 확인
kubectl get pods -n istio-system

# LoadBalancer 서비스 확인 (NLB 주소 확인)
kubectl get svc -n istio-system istio-ingressgateway

# LoadBalancer 주소 가져오기
kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Gateway 확인
kubectl get gateway -n ecommerce

# HTTPRoute 확인
kubectl get httproute -n ecommerce

# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce
```

### 3. Istio 설치 검증

```bash
istioctl verify-install
```

### 4. DNS 설정 (선택사항)

LoadBalancer 주소를 DNS에 연결하려면:

```bash
# NLB 주소 확인
NLB_HOSTNAME=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Route53 또는 DNS 서비스에서 설정
# api.ecommerce.com -> $NLB_HOSTNAME
# webhook.ecommerce.com -> $NLB_HOSTNAME
```

## EKS 환경 특화 설정

### 1. LoadBalancer 설정

EKS 환경에서는 Istio Ingress Gateway가 자동으로 AWS Network Load Balancer (NLB)를 생성합니다.

**설정 위치**: `install-istio.sh`

```bash
--set values.gateways.istio-ingressgateway.type=LoadBalancer \
--set values.gateways.istio-ingressgateway.serviceAnnotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
--set values.gateways.istio-ingressgateway.serviceAnnotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing"
```

**NLB 타입 변경** (ALB 사용 시):

```bash
# ALB 사용 (AWS Load Balancer Controller 필요)
--set values.gateways.istio-ingressgateway.serviceAnnotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb-ip" \
--set values.gateways.istio-ingressgateway.serviceAnnotations."alb\.ingress\.kubernetes\.io/target-type"="ip"
```

### 2. 인증서 관리

EKS 환경에서 TLS 인증서를 관리하는 방법:

#### 옵션 1: cert-manager 사용 (권장)

```bash
# cert-manager 설치
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# ClusterIssuer 생성 (Let's Encrypt)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: istio
EOF
```

#### 옵션 2: AWS Certificate Manager (ACM) 사용

```bash
# ACM에서 인증서 생성 후
# Gateway 리소스에서 certificateRefs 수정 필요
```

### 3. 리소스 제한

EKS 환경에서 리소스 제한을 설정하려면:

```bash
# Istio 설치 시 리소스 제한 추가
istioctl install \
  --set values.defaultRevision=default \
  --set profile=minimal \
  --set values.gateways.istio-ingressgateway.resources.requests.cpu=500m \
  --set values.gateways.istio-ingressgateway.resources.requests.memory=512Mi \
  --set values.gateways.istio-ingressgateway.resources.limits.cpu=2000m \
  --set values.gateways.istio-ingressgateway.resources.limits.memory=2048Mi \
  -y
```

### 4. 노드 선택 (Node Affinity)

특정 노드 그룹에 Istio Gateway를 배포하려면:

```bash
istioctl install \
  --set values.gateways.istio-ingressgateway.nodeSelector."node-type"="gateway" \
  -y
```

## 리소스 구조

```
istio/
├── install-istio.sh              # Istio 설치 스크립트 (EKS용)
├── uninstall-istio.sh            # Istio 제거 스크립트
├── README.md                      # 이 파일
└── resources/                     # Istio 구성 리소스
    ├── 00-gateway-class.yaml
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

### CloudWatch 통합

EKS 환경에서 CloudWatch로 메트릭을 전송하려면:

```bash
# CloudWatch Container Insights 활성화
# EKS 클러스터에 CloudWatch Agent 설치 필요
```

## 문제 해결

### 1. LoadBalancer가 생성되지 않음

```bash
# LoadBalancer 서비스 확인
kubectl get svc -n istio-system istio-ingressgateway

# 이벤트 확인
kubectl describe svc -n istio-system istio-ingressgateway

# IAM 권한 확인
# EKS 노드 그룹에 ELB 권한이 있는지 확인
```

### 2. Gateway가 준비되지 않음

```bash
# Gateway 상태 확인
kubectl get gateway -n ecommerce

# Gateway 이벤트 확인
kubectl describe gateway ecommerce-gateway -n ecommerce

# Istio Gateway Pod 확인
kubectl get pods -n istio-system -l app=istio-ingressgateway

# Pod 로그 확인
kubectl logs -n istio-system -l app=istio-ingressgateway
```

### 3. mTLS 연결 실패

```bash
# PeerAuthentication 확인
kubectl get peerauthentication -n ecommerce

# mTLS 상태 확인
istioctl authn tls-check <pod-name>.<namespace> <service-name>

# 인증서 확인
istioctl proxy-config secret <pod-name>.<namespace>
```

### 4. JWT 인증 실패

```bash
# RequestAuthentication 확인
kubectl get requestauthentication -n ecommerce

# AuthorizationPolicy 확인
kubectl get authorizationpolicy -n ecommerce

# JWT 검증 로그 확인
kubectl logs -n istio-system -l app=istio-ingressgateway | grep jwt
```

### 5. Rate Limiting 동작 안 함

```bash
# EnvoyFilter 확인
kubectl get envoyfilter -n ecommerce

# Redis 연결 확인
kubectl get svc redis -n ecommerce

# Rate Limit ConfigMap 확인
kubectl get configmap ratelimit-config -n ecommerce
```

### 6. NLB 타임아웃

EKS NLB는 기본 타임아웃이 350초입니다. 더 긴 타임아웃이 필요한 경우:

```bash
# 서비스 어노테이션 추가
kubectl annotate svc istio-ingressgateway -n istio-system \
  service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout=3600
```

### 7. DNS 해석 문제

```bash
# CoreDNS 확인
kubectl get pods -n kube-system -l k8s-app=kube-dns

# DNS 로그 확인
kubectl logs -n kube-system -l k8s-app=kube-dns

# 서비스 DNS 확인
nslookup order-service.ecommerce.svc.cluster.local
```

## 제거 방법

### 1. Istio 구성 리소스만 제거

```bash
./uninstall-istio.sh
```

### 2. Istio Control Plane 포함 완전 제거

```bash
REMOVE_CONTROL_PLANE=true ./uninstall-istio.sh
```

## 참고 자료

- [Istio 공식 문서](https://istio.io/latest/docs/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [EKS Load Balancer 가이드](https://docs.aws.amazon.com/eks/latest/userguide/load-balancing.html)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)
- [k3d 환경 Istio 설정](../k8s-dev-k3d/istio/README.md)

