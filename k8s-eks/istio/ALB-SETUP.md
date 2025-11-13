# ALB 사용 설정 가이드

현재 Istio Gateway API를 사용하면 기본적으로 **Classic Load Balancer** 또는 **NLB**가 생성됩니다. **ALB**를 사용하려면 추가 설정이 필요합니다.

## 🔍 현재 상황

Gateway API를 사용할 때 Istio가 자동으로 Service를 생성하는데, 이때 어노테이션이 제대로 적용되지 않아 Classic Load Balancer가 생성될 수 있습니다.

## 🎯 ALB 사용 방법

### 방법 1: Gateway 리소스에 어노테이션 추가 (권장)

Gateway 리소스에 어노테이션을 추가하면, Istio가 생성하는 Service에 어노테이션이 전달됩니다.

#### 1. Gateway 리소스 수정

`k8s-eks/istio/resources/02-gateway-main.yaml` 파일에 어노테이션 추가:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ecommerce-gateway
  namespace: ecommerce
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    # NLB 사용 (현재 설정)
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
```

**⚠️ 주의**: Gateway API에서 Service 어노테이션은 Istio 버전에 따라 다르게 동작할 수 있습니다.

### 방법 2: AWS Load Balancer Controller 사용 (ALB 전용)

ALB를 사용하려면 **AWS Load Balancer Controller**를 설치하고, Ingress 리소스를 사용해야 합니다.

#### 1. AWS Load Balancer Controller 설치

```bash
# Helm 저장소 추가
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# AWS Load Balancer Controller 설치
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<YOUR_CLUSTER_NAME> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

#### 2. IAM 정책 및 역할 설정

```bash
# IAM 정책 다운로드
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

# IAM 정책 생성
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# IAM 역할 생성 (IRSA)
eksctl create iamserviceaccount \
  --cluster=<YOUR_CLUSTER_NAME> \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve
```

#### 3. Gateway 대신 Ingress 사용

ALB를 사용하려면 Gateway API 대신 Ingress를 사용해야 합니다:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ecommerce-ingress
  namespace: ecommerce
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: <ACM_CERTIFICATE_ARN>
spec:
  ingressClassName: alb
  rules:
  - host: api.ecommerce.com
    http:
      paths:
      - path: /api/v1/orders
        pathType: Prefix
        backend:
          service:
            name: order-service
            port:
              number: 8080
```

**⚠️ 단점**: Gateway API의 고급 기능을 사용할 수 없습니다.

### 방법 3: Istio Ingress Gateway 직접 설정 (권장하지 않음)

Istio의 기존 Ingress Gateway를 사용하고 ALB를 앞에 두는 방법:

```bash
# Istio Ingress Gateway를 NodePort로 설정
istioctl install \
  --set values.gateways.istio-ingressgateway.type=NodePort \
  --set values.gateways.istio-ingressgateway.serviceAnnotations."alb\.ingress\.kubernetes\.io/target-type"="ip" \
  -y
```

## 📊 비교

| 방법 | 장점 | 단점 |
|------|------|------|
| **NLB (현재)** | Gateway API 완전 지원, 빠른 성능 | ALB 기능 부족 (WAF, Path-based routing 등) |
| **ALB + Ingress** | WAF, Path-based routing 지원 | Gateway API 기능 제한 |
| **ALB + Gateway API** | Gateway API + ALB 기능 | 복잡한 설정, 일부 제한 |

## 🎯 권장 사항

### 현재 상황 (NLB 사용)

**장점**:
- Gateway API 완전 지원
- Istio의 모든 기능 사용 가능
- 빠른 성능 (Layer 4)
- 간단한 설정

**단점**:
- ALB의 고급 기능 (WAF, Path-based routing 등) 사용 불가

### ALB가 필요한 경우

다음 기능이 필요하면 ALB를 고려하세요:
- **AWS WAF** 통합
- **Path-based routing** (ALB 레벨)
- **Request/Response 변환**
- **Lambda@Edge** 통합

## 🔧 NLB에서 ALB로 변경하기

### 1. Gateway 리소스 수정

```bash
# Gateway 리소스에 ALB 어노테이션 추가
kubectl annotate gateway ecommerce-gateway -n ecommerce \
  service.beta.kubernetes.io/aws-load-balancer-type="external" \
  service.beta.kubernetes.io/aws-load-balancer-scheme="internet-facing" \
  --overwrite
```

### 2. 기존 Load Balancer 삭제

```bash
# Service 삭제 (Load Balancer도 함께 삭제됨)
kubectl delete svc ecommerce-gateway-istio -n ecommerce

# Gateway 리소스 재생성 (Istio가 새 Service 생성)
kubectl apply -f k8s-eks/istio/resources/02-gateway-main.yaml
```

### 3. AWS Load Balancer Controller 설치 (ALB 사용 시)

```bash
# AWS Load Balancer Controller 설치
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$(kubectl config view -o jsonpath='{.clusters[0].name}') \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

## ⚠️ 주의사항

1. **Gateway API와 ALB**: Gateway API는 기본적으로 Istio가 관리하는 Load Balancer를 생성합니다. ALB를 직접 사용하려면 추가 설정이 필요합니다.

2. **Istio 버전**: Istio 1.22+ 버전에서 Gateway API를 사용할 때 Service 어노테이션이 제대로 전달되지 않을 수 있습니다.

3. **성능**: NLB는 Layer 4 로드밸런싱으로 더 빠르고, ALB는 Layer 7로 더 많은 기능을 제공합니다.

## 📚 참고 자료

- [Istio Gateway API](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EKS Load Balancer 가이드](https://docs.aws.amazon.com/eks/latest/userguide/load-balancing.html)

