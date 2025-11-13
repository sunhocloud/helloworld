# SOPS 빠른 시작 가이드

## 1. 설치

```bash
# SOPS 설치
brew install sops  # macOS
# 또는
curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
chmod +x /usr/local/bin/sops

# helm-secrets 플러그인 설치
helm plugin install https://github.com/jkroepke/helm-secrets

# 설치 확인
sops --version
helm plugin list
```

## 2. AWS KMS 키 생성

```bash
# KMS 키 생성
aws kms create-key \
  --description "SOPS encryption key for c4ang" \
  --region ap-northeast-2

# KMS 키 ARN 확인
KMS_KEY_ARN=$(aws kms create-key \
  --description "SOPS encryption key" \
  --region ap-northeast-2 \
  --query 'KeyMetadata.Arn' \
  --output text)

echo "KMS Key ARN: $KMS_KEY_ARN"
```

## 3. .sops.yaml 설정

프로젝트 루트의 `.sops.yaml` 파일에서 KMS 키 ARN을 실제 값으로 변경:

```yaml
creation_rules:
  - kms: 'arn:aws:kms:ap-northeast-2:123456789012:key/abcd1234-5678-90ef-ghij-klmnopqrstuv'
    path_regex: .*secrets\.enc\.yaml$
```

## 4. 시크릿 파일 생성

```bash
cd helm/services/customer-service

# 예시 파일 복사
cp values.secrets.yaml.example values.secrets.yaml

# 실제 시크릿 값 입력
vi values.secrets.yaml
```

## 5. 시크릿 암호화

```bash
# 평문 파일을 암호화
sops -e values.secrets.yaml > values.secrets.enc.yaml

# 암호화 확인
sops -d values.secrets.enc.yaml  # 복호화해서 내용 확인
```

## 6. Helm 배포

```bash
# helm-secrets로 배포
helm secrets install customer-service \
  ./helm/services/customer-service \
  -f values.yaml \
  -f values.secrets.enc.yaml \
  -n ecommerce \
  --create-namespace

# 또는 업그레이드
helm secrets upgrade customer-service \
  ./helm/services/customer-service \
  -f values.yaml \
  -f values.secrets.enc.yaml \
  -n ecommerce
```

## 7. 시크릿 편집

```bash
# SOPS로 암호화된 파일 직접 편집 (자동 복호화/암호화)
sops helm/services/customer-service/values.secrets.enc.yaml

# 또는 평문 파일 편집 후 재암호화
vi values.secrets.yaml
sops -e values.secrets.yaml > values.secrets.enc.yaml
```

## 8. Git에 커밋

```bash
# 암호화된 파일만 커밋 (평문 파일은 .gitignore에 의해 제외됨)
git add values.secrets.enc.yaml
git commit -m "Add encrypted secrets"
```

## 🔒 보안 체크리스트

- [ ] `.sops.yaml`에 올바른 KMS 키 ARN 설정
- [ ] `values.secrets.yaml`이 `.gitignore`에 포함되어 있는지 확인
- [ ] 암호화된 `values.secrets.enc.yaml`만 Git에 커밋
- [ ] KMS 키 접근 권한이 적절히 설정되어 있는지 확인

## 🐛 문제 해결

### SOPS가 KMS 키에 접근할 수 없음

```bash
# AWS 자격 증명 확인
aws sts get-caller-identity

# KMS 키 권한 확인
aws kms describe-key --key-id <KEY_ID>
```

### helm-secrets가 작동하지 않음

```bash
# 플러그인 재설치
helm plugin uninstall secrets
helm plugin install https://github.com/jkroepke/helm-secrets
```

## 📚 참고

- [SOPS GitHub](https://github.com/mozilla/sops)
- [helm-secrets Plugin](https://github.com/jkroepke/helm-secrets)
- [전체 가이드](./secrets-management-eks.md)

