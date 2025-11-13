# EKS에서의 키 관리 가이드

## 🎯 어떤 방식을 선택할까?

### 방법 1: SOPS + helm-secrets (권장 ⭐)

**언제 사용?**
- Helm 차트 기반 배포
- GitOps (ArgoCD 등) 사용
- 개발자가 values.yaml 직접 수정
- **values.yaml 구조를 그대로 유지하고 싶을 때**

**장점:**
- Helm 차트 구조 그대로 사용
- 로컬에서 평문으로 편집 → Git에 암호화해서 저장
- 비용 효율적 (KMS 비용만)
- 환경별로 다른 KMS 키 사용 가능

**단점:**
- 자동 로테이션 불가
- CI/CD에 SOPS 통합 필요

### 방법 2: AWS Secrets Manager + External Secrets Operator

**언제 사용?**
- 자동 로테이션 필요
- AWS 네이티브 관리형 솔루션 선호
- 중앙 집중식 관리 필요
- 감사 로그 필수

**장점:**
- 자동 로테이션 지원
- AWS 네이티브 통합
- 중앙 집중식 관리
- 감사 로그 자동 수집

**단점:**
- 비용 발생 ($0.40/secret/month)
- IAM 설정 필요

## 🚀 방법 1: SOPS + helm-secrets (간단 가이드)

### 1. 설치

```bash
# SOPS 설치
brew install sops  # macOS

# helm-secrets 플러그인 설치
helm plugin install https://github.com/jkroepke/helm-secrets
```

### 2. AWS KMS 키 생성

```bash
# KMS 키 생성
aws kms create-key --description "SOPS key for c4ang" --region ap-northeast-2

# KMS 키 ARN 확인
KMS_KEY_ARN=$(aws kms create-key --description "SOPS key" --region ap-northeast-2 --query 'KeyMetadata.Arn' --output text)
echo $KMS_KEY_ARN
```

### 3. .sops.yaml 생성 (프로젝트 루트)

```yaml
# .sops.yaml
creation_rules:
  - kms: 'arn:aws:kms:ap-northeast-2:ACCOUNT_ID:key/KMS_KEY_ID'
    path_regex: .*secrets\.enc\.yaml$
```

### 4. 시크릿 파일 생성 및 암호화

```bash
# 1. 평문 시크릿 파일 생성
cat > helm/services/customer-service/values.secrets.yaml <<EOF
database:
  username: admin
  password: super-secret-password
EOF

# 2. .gitignore에 평문 파일 추가
echo "*.secrets.yaml" >> .gitignore

# 3. 암호화
sops -e helm/services/customer-service/values.secrets.yaml > \
  helm/services/customer-service/values.secrets.enc.yaml

# 4. Git에 암호화된 파일만 커밋
git add helm/services/customer-service/values.secrets.enc.yaml
```

### 5. Helm 배포

```bash
# helm-secrets로 배포
helm secrets install customer-service \
  ./helm/services/customer-service \
  -f values.yaml \
  -f values.secrets.enc.yaml \
  -n ecommerce
```

### 6. 시크릿 편집

```bash
# SOPS로 암호화된 파일 직접 편집 (자동 복호화/암호화)
sops helm/services/customer-service/values.secrets.enc.yaml
```

## 🚀 방법 2: AWS Secrets Manager + External Secrets Operator

### 1. External Secrets Operator 설치

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system --create-namespace
```

### 2. IAM 역할 생성 (IRSA)

```bash
# 1. IAM 정책 생성
aws iam create-policy \
  --policy-name ExternalSecretsPolicy \
  --policy-document file://k8s-eks/secrets/iam/external-secrets-policy.json

# 2. IAM 역할 생성 및 ServiceAccount 연결
# (EKS OIDC 제공자 필요)
kubectl apply -f k8s-eks/secrets/service-account.yaml
```

### 3. SecretStore 생성

```bash
kubectl apply -f k8s-eks/secrets/secret-store.yaml
```

### 4. AWS Secrets Manager에 시크릿 저장

```bash
aws secretsmanager create-secret \
  --name c4ang/customer-service/database \
  --secret-string '{"username":"admin","password":"secret123"}' \
  --region ap-northeast-2
```

### 5. ExternalSecret 생성

```bash
kubectl apply -f k8s-eks/secrets/external-secrets/customer-service-db.yaml
```

### 6. Secret 자동 생성 확인

```bash
# ExternalSecret이 Kubernetes Secret을 자동 생성
kubectl get secret customer-service-db-secret -n ecommerce
```

## 📊 비교 요약

| 항목 | SOPS + helm-secrets | AWS Secrets Manager + ESO |
|------|---------------------|---------------------------|
| **Helm 호환성** | ⭐⭐⭐ 매우 우수 (구조 유지) | ⭐⭐ 우수 (Secret 생성) |
| **비용** | KMS 비용만 | $0.40/secret/month |
| **자동 로테이션** | ❌ | ✅ |
| **설정 복잡도** | 낮음 | 중간 |
| **GitOps** | ⭐⭐⭐ 매우 좋음 | ⭐⭐ 좋음 |

## 🎯 선택 가이드

### SOPS를 선택하세요
- ✅ Helm 차트 기반 배포
- ✅ GitOps (ArgoCD) 사용
- ✅ values.yaml 구조 유지
- ✅ 비용 절감 필요
- ✅ 개발자가 직접 수정

### AWS Secrets Manager를 선택하세요
- ✅ 자동 로테이션 필요
- ✅ 프로덕션 환경
- ✅ 중앙 집중식 관리
- ✅ 감사 로그 필수
- ✅ AWS 네이티브 선호

## 📁 프로젝트 구조

```
c4ang-infra/
├── .sops.yaml.example                    # SOPS 설정 예시
├── helm/services/customer-service/
│   ├── values.yaml                       # 일반 설정
│   └── values.secrets.enc.yaml          # 암호화된 시크릿 (SOPS)
└── k8s-eks/secrets/                     # AWS Secrets Manager 방식
    ├── secret-store.yaml                 # SecretStore 정의
    ├── service-account.yaml              # ServiceAccount (IRSA)
    ├── external-secrets/
    │   └── customer-service-db.yaml     # ExternalSecret
    └── iam/
        └── external-secrets-policy.json # IAM 정책
```

## 🔒 보안 모범 사례

1. **환경별 키 분리**
   - 개발/스테이징/프로덕션 각각 다른 KMS 키 사용

2. **.gitignore 설정**
   - 평문 시크릿 파일은 Git에 커밋하지 않기

3. **최소 권한 원칙**
   - 필요한 시크릿만 접근 가능하도록 IAM 정책 설정

4. **자동 로테이션 (프로덕션)**
   - AWS Secrets Manager 사용 시 자동 로테이션 설정

## 📚 참고 자료

- [SOPS GitHub](https://github.com/mozilla/sops)
- [helm-secrets Plugin](https://github.com/jkroepke/helm-secrets)
- [External Secrets Operator](https://external-secrets.io/)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
