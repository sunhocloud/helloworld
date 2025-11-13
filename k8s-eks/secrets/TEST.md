# EKS에서 시크릿 관리 테스트 가이드

EKS 환경에서 시크릿 관리를 테스트하는 방법입니다.

## 🎯 테스트 방법 선택

### 방법 1: AWS Secrets Manager + External Secrets Operator (권장)
- 프로덕션 환경에 적합
- 자동 로테이션 지원
- 중앙 집중식 관리

### 방법 2: SOPS + helm-secrets
- GitOps 환경에 적합
- Helm 차트 구조 유지
- 비용 효율적

---

## 🚀 방법 1: AWS Secrets Manager + External Secrets Operator 테스트

### 1. 사전 준비

```bash
# EKS 클러스터 접근 확인
aws eks update-kubeconfig --name <CLUSTER_NAME> --region ap-northeast-2
kubectl get nodes

# AWS 계정 ID 확인
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# EKS OIDC 제공자 확인
export CLUSTER_NAME=<YOUR_CLUSTER_NAME>
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text
```

### 2. External Secrets Operator 설치

```bash
# Helm 저장소 추가
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# External Secrets Operator 설치
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true

# 설치 확인
kubectl get pods -n external-secrets-system
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=external-secrets -n external-secrets-system --timeout=300s
```

### 3. IAM 역할 생성 (IRSA)

#### 3.1 IAM 정책 생성

```bash
# IAM 정책 생성
aws iam create-policy \
  --policy-name ExternalSecretsOperatorPolicy \
  --policy-document file://k8s-eks/secrets/iam/external-secrets-policy.json \
  --region ap-northeast-2

# 정책 ARN 확인
export POLICY_ARN=$(aws iam list-policies \
  --query "Policies[?PolicyName=='ExternalSecretsOperatorPolicy'].Arn" \
  --output text \
  --region ap-northeast-2)
echo "Policy ARN: $POLICY_ARN"
```

#### 3.2 IAM 역할 생성

```bash
# EKS OIDC 제공자 URL 추출
export OIDC_PROVIDER=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed -e "s/^https:\/\///")
echo "OIDC Provider: $OIDC_PROVIDER"

# OIDC 제공자 존재 확인
aws iam list-open-id-connect-providers | grep $OIDC_PROVIDER || \
  eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve

# 신뢰 정책 생성
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:external-secrets-system:external-secrets-sa",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# IAM 역할 생성
aws iam create-role \
  --role-name external-secrets-operator-role \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --region ap-northeast-2

# IAM 정책 연결
aws iam attach-role-policy \
  --role-name external-secrets-operator-role \
  --policy-arn $POLICY_ARN \
  --region ap-northeast-2

# 역할 ARN 확인
export ROLE_ARN=$(aws iam get-role \
  --role-name external-secrets-operator-role \
  --query 'Role.Arn' \
  --output text)
echo "Role ARN: $ROLE_ARN"
```

#### 3.3 ServiceAccount에 IAM 역할 연결

```bash
# service-account.yaml 파일 수정 (ACCOUNT_ID를 실제 값으로 변경)
sed "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" k8s-eks/secrets/service-account.yaml > /tmp/service-account.yaml

# ServiceAccount 적용
kubectl apply -f /tmp/service-account.yaml

# ServiceAccount 확인
kubectl get serviceaccount external-secrets-sa -n external-secrets-system -o yaml
```

### 4. SecretStore 생성

```bash
# 네임스페이스 생성
kubectl create namespace ecommerce --dry-run=client -o yaml | kubectl apply -f -

# SecretStore 적용
kubectl apply -f k8s-eks/secrets/secret-store.yaml

# SecretStore 상태 확인
kubectl get secretstore aws-secrets-manager -n ecommerce
kubectl describe secretstore aws-secrets-manager -n ecommerce
```

### 5. AWS Secrets Manager에 시크릿 저장

```bash
# 테스트용 시크릿 생성
aws secretsmanager create-secret \
  --name c4ang/customer-service/database \
  --description "Customer Service Database Credentials (Test)" \
  --secret-string '{"username":"test_user","password":"test_password_123"}' \
  --region ap-northeast-2

# 시크릿 확인
aws secretsmanager get-secret-value \
  --secret-id c4ang/customer-service/database \
  --region ap-northeast-2 \
  --query SecretString --output text
```

### 6. ExternalSecret 생성

```bash
# ExternalSecret 적용
kubectl apply -f k8s-eks/secrets/external-secrets/customer-service-db.yaml

# ExternalSecret 상태 확인
kubectl get externalsecret customer-service-db-secret -n ecommerce
kubectl describe externalsecret customer-service-db-secret -n ecommerce

# Kubernetes Secret 자동 생성 확인 (약 1분 소요)
kubectl get secret customer-service-db-secret -n ecommerce

# Secret 내용 확인
kubectl get secret customer-service-db-secret -n ecommerce -o jsonpath='{.data.username}' | base64 -d
kubectl get secret customer-service-db-secret -n ecommerce -o jsonpath='{.data.password}' | base64 -d
```

### 7. 테스트 검증

```bash
# ExternalSecret 이벤트 확인
kubectl describe externalsecret customer-service-db-secret -n ecommerce

# External Secrets Operator 로그 확인
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets --tail=50

# Secret이 정상적으로 생성되었는지 확인
kubectl get secret customer-service-db-secret -n ecommerce -o yaml
```

### 8. 시크릿 업데이트 테스트

```bash
# AWS Secrets Manager에서 시크릿 업데이트
aws secretsmanager put-secret-value \
  --secret-id c4ang/customer-service/database \
  --secret-string '{"username":"test_user","password":"updated_password_456"}' \
  --region ap-northeast-2

# ExternalSecret 새로고침 (refreshInterval이 1h이므로 수동 새로고침)
kubectl annotate externalsecret customer-service-db-secret \
  force-sync=$(date +%s) \
  -n ecommerce \
  --overwrite

# 업데이트 확인 (약 1분 소요)
sleep 60
kubectl get secret customer-service-db-secret -n ecommerce -o jsonpath='{.data.password}' | base64 -d
```

### 9. 정리 (테스트 완료 후)

```bash
# ExternalSecret 삭제
kubectl delete externalsecret customer-service-db-secret -n ecommerce

# Kubernetes Secret 삭제
kubectl delete secret customer-service-db-secret -n ecommerce

# AWS Secrets Manager 시크릿 삭제
aws secretsmanager delete-secret \
  --secret-id c4ang/customer-service/database \
  --force-delete-without-recovery \
  --region ap-northeast-2

# SecretStore 삭제
kubectl delete secretstore aws-secrets-manager -n ecommerce

# External Secrets Operator 삭제 (선택사항)
helm uninstall external-secrets -n external-secrets-system
```

---

## 🚀 방법 2: SOPS + helm-secrets 테스트

### 1. 사전 준비

```bash
# SOPS 설치
brew install sops  # macOS
# 또는
curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops && chmod +x /usr/local/bin/sops

# helm-secrets 플러그인 설치
helm plugin install https://github.com/jkroepke/helm-secrets

# 설치 확인
sops --version
helm plugin list
```

### 2. AWS KMS 키 생성

```bash
# KMS 키 생성
aws kms create-key \
  --description "SOPS encryption key for c4ang (Test)" \
  --region ap-northeast-2

# KMS 키 ARN 확인
export KMS_KEY_ARN=$(aws kms create-key \
  --description "SOPS encryption key" \
  --region ap-northeast-2 \
  --query 'KeyMetadata.Arn' \
  --output text)
echo "KMS Key ARN: $KMS_KEY_ARN"

# KMS 키 ID 추출
export KMS_KEY_ID=$(echo $KMS_KEY_ARN | awk -F'/' '{print $NF}')
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "KMS Key ID: $KMS_KEY_ID"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
```

### 3. .sops.yaml 설정

```bash
# .sops.yaml 파일 수정
sed -i.bak "s/ACCOUNT_ID/$AWS_ACCOUNT_ID/g" .sops.yaml
sed -i.bak "s/KMS_KEY_ID/$KMS_KEY_ID/g" .sops.yaml

# .sops.yaml 확인
cat .sops.yaml
```

### 4. 시크릿 파일 생성 및 암호화

```bash
# 시크릿 파일 생성
cat > helm/services/customer-service/values.secrets.yaml <<EOF
database:
  username: test_user
  password: test_password_123
EOF

# 암호화
sops -e helm/services/customer-service/values.secrets.yaml > \
  helm/services/customer-service/values.secrets.enc.yaml

# 암호화 확인
sops -d helm/services/customer-service/values.secrets.enc.yaml
```

### 5. Helm 배포 테스트

```bash
# EKS 클러스터 접근
aws eks update-kubeconfig --name <CLUSTER_NAME> --region ap-northeast-2

# 네임스페이스 생성
kubectl create namespace ecommerce --dry-run=client -o yaml | kubectl apply -f -

# helm-secrets로 배포
helm secrets install customer-service \
  ./helm/services/customer-service \
  -f helm/services/customer-service/values.yaml \
  -f helm/services/customer-service/values.secrets.enc.yaml \
  -n ecommerce \
  --create-namespace \
  --dry-run

# 실제 배포 (dry-run 성공 시)
helm secrets install customer-service \
  ./helm/services/customer-service \
  -f helm/services/customer-service/values.yaml \
  -f helm/services/customer-service/values.secrets.enc.yaml \
  -n ecommerce \
  --create-namespace
```

### 6. 배포 확인

```bash
# Helm release 확인
helm list -n ecommerce

# Pod 확인
kubectl get pods -n ecommerce

# Secret 확인 (Helm이 생성한 경우)
kubectl get secrets -n ecommerce

# 환경 변수 확인
kubectl get deployment customer-service -n ecommerce -o yaml | grep -A 10 env:
```

### 7. 시크릿 편집 테스트

```bash
# SOPS로 암호화된 파일 직접 편집
sops helm/services/customer-service/values.secrets.enc.yaml

# 또는 평문 파일 편집 후 재암호화
vi helm/services/customer-service/values.secrets.yaml
sops -e helm/services/customer-service/values.secrets.enc.yaml > \
  helm/services/customer-service/values.secrets.enc.yaml.new
mv helm/services/customer-service/values.secrets.enc.yaml.new \
  helm/services/customer-service/values.secrets.enc.yaml

# Helm 업그레이드
helm secrets upgrade customer-service \
  ./helm/services/customer-service \
  -f helm/services/customer-service/values.yaml \
  -f helm/services/customer-service/values.secrets.enc.yaml \
  -n ecommerce
```

### 8. 정리 (테스트 완료 후)

```bash
# Helm release 삭제
helm uninstall customer-service -n ecommerce

# 시크릿 파일 삭제
rm -f helm/services/customer-service/values.secrets.yaml
rm -f helm/services/customer-service/values.secrets.enc.yaml

# KMS 키 삭제 (선택사항, 비용 발생)
aws kms schedule-key-deletion \
  --key-id $KMS_KEY_ID \
  --pending-window-in-days 7 \
  --region ap-northeast-2
```

---

## 🔍 문제 해결

### ExternalSecret이 동기화되지 않음

```bash
# ExternalSecret 상태 확인
kubectl describe externalsecret customer-service-db-secret -n ecommerce

# SecretStore 상태 확인
kubectl describe secretstore aws-secrets-manager -n ecommerce

# External Secrets Operator 로그 확인
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets --tail=100

# IAM 역할 확인
kubectl get serviceaccount external-secrets-sa -n external-secrets-system -o yaml | grep role-arn

# AWS 자격 증명 확인
aws sts get-caller-identity
```

### SOPS가 KMS 키에 접근할 수 없음

```bash
# AWS 자격 증명 확인
aws sts get-caller-identity

# KMS 키 권한 확인
aws kms describe-key --key-id $KMS_KEY_ID --region ap-northeast-2

# KMS 키 정책 확인
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default --region ap-northeast-2
```

### helm-secrets가 작동하지 않음

```bash
# 플러그인 재설치
helm plugin uninstall secrets
helm plugin install https://github.com/jkroepke/helm-secrets

# SOPS 설치 확인
sops --version

# 환경 변수 확인
echo $SOPS_AGE_KEY_FILE
```

---

## ✅ 체크리스트

### AWS Secrets Manager + External Secrets Operator

- [ ] EKS 클러스터 접근 가능
- [ ] External Secrets Operator 설치 완료
- [ ] IAM 역할 생성 및 ServiceAccount 연결
- [ ] SecretStore 생성 및 정상 동작
- [ ] AWS Secrets Manager에 시크릿 저장
- [ ] ExternalSecret 생성 및 Kubernetes Secret 자동 생성
- [ ] 시크릿 업데이트 테스트 성공

### SOPS + helm-secrets

- [ ] SOPS 및 helm-secrets 설치 완료
- [ ] AWS KMS 키 생성 및 .sops.yaml 설정
- [ ] 시크릿 파일 암호화 성공
- [ ] Helm 배포 성공
- [ ] 시크릿 편집 및 업데이트 테스트 성공

---

## 📚 참고

- [External Secrets Operator 문서](https://external-secrets.io/)
- [AWS Secrets Manager 문서](https://docs.aws.amazon.com/secretsmanager/)
- [SOPS 공식 문서](https://github.com/mozilla/sops)
- [helm-secrets Plugin](https://github.com/jkroepke/helm-secrets)
- [시크릿 관리 가이드](../docs/secrets-management-eks.md)


