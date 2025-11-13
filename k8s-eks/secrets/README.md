# EKS 시크릿 관리

이 디렉토리는 EKS 환경에서 사용하는 시크릿 관리 설정을 포함합니다.

## 📁 파일 구조

```
k8s-eks/secrets/
├── README.md                           # 이 파일
├── secret-store.yaml                   # SecretStore 정의 (AWS Secrets Manager)
├── service-account.yaml                # ServiceAccount (IRSA)
├── external-secrets/
│   └── customer-service-db.yaml       # ExternalSecret 예시
└── iam/
    └── external-secrets-policy.json   # IAM 정책
```

## 🚀 사용 방법

### AWS Secrets Manager + External Secrets Operator

1. **External Secrets Operator 설치**
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system --create-namespace
```

2. **IAM 역할 설정** (IRSA)
```bash
# IAM 정책 생성
aws iam create-policy \
  --policy-name ExternalSecretsPolicy \
  --policy-document file://iam/external-secrets-policy.json

# ServiceAccount에 IAM 역할 연결
kubectl apply -f service-account.yaml
```

3. **SecretStore 생성**
```bash
kubectl apply -f secret-store.yaml
```

4. **AWS Secrets Manager에 시크릿 저장**
```bash
aws secretsmanager create-secret \
  --name c4ang/customer-service/database \
  --secret-string '{"username":"admin","password":"secret123"}' \
  --region ap-northeast-2
```

5. **ExternalSecret 적용**
```bash
kubectl apply -f external-secrets/customer-service-db.yaml
```

## 🧪 테스트

EKS에서 시크릿 관리를 테스트하는 방법은 [TEST.md](./TEST.md)를 참고하세요.

## 📝 참고

더 자세한 내용은 [docs/secrets-management-eks.md](../../docs/secrets-management-eks.md)를 참고하세요.

