# k3d 로컬 환경에서 SOPS 사용 가이드

로컬 k3d 환경에서 SOPS + Age를 사용하여 시크릿을 암호화하여 관리하는 방법입니다.

## 🎯 왜 로컬에서 SOPS를 사용하나요?

- **Git에 안전하게 커밋**: 암호화된 시크릿 파일을 Git에 커밋 가능
- **팀 협업**: 팀원들과 시크릿을 안전하게 공유
- **일관성**: 로컬과 프로덕션 환경에서 동일한 워크플로우 사용

## 🚀 빠른 시작

### 1. 필수 도구 설치

```bash
# Age 설치 (로컬 환경용 암호화 키)
brew install age

# SOPS 설치
brew install sops

# helm-secrets 플러그인 설치
helm plugin install https://github.com/jkroepke/helm-secrets
```

### 2. Age 키 생성 및 설정

```bash
# 프로젝트 루트에서 실행
./k8s-dev-k3d/scripts/setup-sops-age.sh
```

이 스크립트는 다음을 수행합니다:
- Age 키 생성 (`~/.config/sops/age/keys.txt`)
- `.sops.yaml` 파일에 Age 공개 키 설정
- 키 파일 위치 안내

### 3. 시크릿 파일 생성

```bash
cd k8s-dev-k3d/values

# PostgreSQL 시크릿 파일 생성
cp postgresql.secrets.yaml.example postgresql.secrets.yaml

# 실제 시크릿 값 입력 (선택사항, 기본값 사용 가능)
vi postgresql.secrets.yaml

# 암호화
sops -e postgresql.secrets.yaml > postgresql.secrets.enc.yaml

# Redis 시크릿 파일 생성
cp redis.secrets.yaml.example redis.secrets.yaml
sops -e redis.secrets.yaml > redis.secrets.enc.yaml
```

### 4. Helm 배포 (SOPS 사용)

```bash
export KUBECONFIG=$(pwd)/k8s-dev-k3d/kubeconfig/config

# helm-secrets로 배포
helm secrets upgrade --install postgresql \
  ../../helm/statefulset-base/postgresql \
  --namespace msa-quality \
  --create-namespace \
  -f postgresql.yaml \
  -f postgresql.secrets.enc.yaml

# Redis도 동일하게
helm secrets upgrade --install redis \
  ../../helm/statefulset-base/redis \
  --namespace msa-quality \
  --create-namespace \
  -f redis.yaml \
  -f redis.secrets.enc.yaml
```

## 📝 사용 방법

### 시크릿 편집

```bash
# 방법 1: SOPS로 암호화된 파일 직접 편집 (권장)
sops k8s-dev-k3d/values/postgresql.secrets.enc.yaml

# 방법 2: 평문 파일 편집 후 재암호화
vi k8s-dev-k3d/values/postgresql.secrets.yaml
sops -e k8s-dev-k3d/values/postgresql.secrets.yaml > \
  k8s-dev-k3d/values/postgresql.secrets.enc.yaml
```

### 시크릿 확인

```bash
# 암호화된 파일 내용 확인 (복호화)
sops -d k8s-dev-k3d/values/postgresql.secrets.enc.yaml

# 특정 키만 확인
sops -d k8s-dev-k3d/values/postgresql.secrets.enc.yaml | \
  yq '.auth.password'
```

### Git에 커밋

```bash
# 암호화된 파일만 커밋 (평문 파일은 .gitignore에 의해 제외됨)
git add k8s-dev-k3d/values/*.secrets.enc.yaml
git commit -m "Add encrypted secrets for k3d local environment"
```

## 🔒 보안 모범 사례

### 1. Age 키 관리

```bash
# Age 키 파일 위치
~/.config/sops/age/keys.txt

# 키 파일 권한 확인 (읽기 전용)
chmod 600 ~/.config/sops/age/keys.txt

# 키 파일 백업 (안전한 곳에 보관)
cp ~/.config/sops/age/keys.txt ~/backup/sops-age-keys.txt
```

### 2. 팀 협업

```bash
# 1. Age 공개 키를 팀과 공유 (.sops.yaml에 이미 포함됨)
# 2. 팀원들이 같은 Age 공개 키로 암호화된 파일 사용
# 3. 각자 Age 개인 키는 안전하게 보관

# 팀원이 Age 키 설정하는 방법
./k8s-dev-k3d/scripts/setup-sops-age.sh
```

### 3. .gitignore 설정

```bash
# 평문 시크릿 파일은 Git에 커밋하지 않음
# .gitignore에 이미 포함되어 있음:
# *.secrets.yaml
# **/values.secrets.yaml
```

## 🐛 문제 해결

### SOPS가 Age 키를 찾을 수 없음

```bash
# Age 키 파일 확인
ls -la ~/.config/sops/age/keys.txt

# 환경 변수 설정 (필요시)
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Age 키 재생성
./k8s-dev-k3d/scripts/setup-sops-age.sh
```

### .sops.yaml의 Age 공개 키가 잘못됨

```bash
# Age 공개 키 확인
cat ~/.config/sops/age/keys.txt | grep "public key"

# .sops.yaml 확인
grep "age:" .sops.yaml

# 스크립트로 재설정
./k8s-dev-k3d/scripts/setup-sops-age.sh
```

### helm-secrets가 작동하지 않음

```bash
# 플러그인 재설치
helm plugin uninstall secrets
helm plugin install https://github.com/jkroepke/helm-secrets

# SOPS 설치 확인
sops --version
```

## 📊 평문 관리 vs SOPS

| 항목 | 평문 관리 | SOPS + Age |
|------|----------|------------|
| **설정 복잡도** | 간단 | 중간 |
| **Git 커밋** | 불가능 | 가능 (암호화) |
| **팀 협업** | 어려움 | 쉬움 |
| **보안** | 낮음 | 높음 |
| **사용 시나리오** | 로컬 개발만 | 로컬 + 팀 협업 |

## 🔄 마이그레이션

### 평문에서 SOPS로 마이그레이션

```bash
# 1. 기존 values 파일에서 시크릿 추출
# values/postgresql.yaml의 auth 섹션을
# values/postgresql.secrets.yaml로 복사

# 2. 암호화
sops -e postgresql.secrets.yaml > postgresql.secrets.enc.yaml

# 3. values/postgresql.yaml에서 시크릿 제거
# (또는 참조로 변경)

# 4. Helm 배포 시 암호화된 파일 사용
helm secrets upgrade --install postgresql \
  ../../helm/statefulset-base/postgresql \
  -f postgresql.yaml \
  -f postgresql.secrets.enc.yaml
```

## 📚 참고

- [SOPS 공식 문서](https://github.com/mozilla/sops)
- [Age 공식 문서](https://github.com/FiloSottile/age)
- [helm-secrets Plugin](https://github.com/jkroepke/helm-secrets)
- [시크릿 관리 전체 가이드](../../docs/secrets-management-eks.md)

