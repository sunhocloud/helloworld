# k8s-dev-k3d 로컬 환경 구축 가이드

k3d를 사용한 로컬 Kubernetes 환경 구축 및 관리 스크립트입니다.

## 📁 디렉토리 구조

```
k8s-dev-k3d/
├── install-k3s.sh              # k3d 설치 및 클러스터 부트스트랩
├── scripts/
│   ├── start-environment.sh    # 로컬 환경 시작
│   ├── stop-environment.sh     # 로컬 환경 중지
│   ├── cleanup.sh              # k3d 리소스 정리
│   └── setup-sops-age.sh       # SOPS Age 키 설정 (로컬 환경용)
├── values/
│   ├── airflow.yaml            # (선택) Airflow values
│   ├── postgresql.yaml         # PostgreSQL values
│   ├── postgresql.secrets.yaml.example  # PostgreSQL 시크릿 예시
│   ├── redis.yaml              # Redis values
│   └── redis.secrets.yaml.example       # Redis 시크릿 예시
├── kubeconfig/                 # kubeconfig 파일 저장 디렉토리
└── README.md
```

## 🚀 빠른 시작

### 1. k3d 클러스터 설치 및 생성

```bash
cd k8s-dev-k3d
./install-k3s.sh
```

이 스크립트는 다음을 수행합니다:
- k3d 자동 설치 (필요시)
- Helm 자동 설치 (필요시)
- k3d 클러스터 생성
- kubeconfig 설정
- Helm 저장소 추가

### 2. SOPS 설정 (로컬 환경용, 선택사항)

로컬에서 시크릿을 암호화하여 관리하려면:

```bash
# Age 설치
brew install age  # macOS

# SOPS 설치
brew install sops

# helm-secrets 플러그인 설치
helm plugin install https://github.com/jkroepke/helm-secrets

# Age 키 생성 및 .sops.yaml 설정
cd ..  # 프로젝트 루트로 이동
./k8s-dev-k3d/scripts/setup-sops-age.sh
```

### 3. 시크릿 파일 생성 (선택사항)

```bash
cd k8s-dev-k3d/values

# PostgreSQL 시크릿 파일 생성
cp postgresql.secrets.yaml.example postgresql.secrets.yaml
vi postgresql.secrets.yaml  # 필요시 수정

# 암호화
sops -e postgresql.secrets.yaml > postgresql.secrets.enc.yaml

# Redis 시크릿 파일 생성
cp redis.secrets.yaml.example redis.secrets.yaml
vi redis.secrets.yaml  # 필요시 수정

# 암호화
sops -e redis.secrets.yaml > redis.secrets.enc.yaml
```

### 4. 로컬 환경 시작

```bash
cd k8s-dev-k3d/scripts
./start-environment.sh
```

이 스크립트는 다음을 수행합니다:
- k3d 클러스터 시작/생성
- 네임스페이스 생성
- Redis와 PostgreSQL 베이스 차트 배포 (필요한 Helm dependencies 자동 빌드 포함)
- 헬스체크 및 상태 출력

> ℹ️ **처음 실행 시 다운로드 지연 안내**
>
> Redis/PostgreSQL 차트는 Bitnami 원격 저장소의 의존성 패키지를 내려받습니다. 처음 한 번은 `helm dependency build` 시간이 다소 걸릴 수 있습니다. 미리 받아 두고 싶다면 아래를 실행하세요.
>
> ```bash
> cd helm
> ./build-dependencies.sh
> ```
>
> 이후에는 캐시된 `charts/*.tgz`를 재사용하므로 훨씬 빠르게 배포됩니다.

### 5. 로컬 환경 중지

```bash
cd k8s-dev-k3d/scripts
./stop-environment.sh
```

## 🔐 시크릿 관리 (로컬 환경)

### 방법 1: 평문 관리 (간단, 기본값 사용)

로컬 개발 환경에서는 `values/postgresql.yaml`과 `values/redis.yaml`에 평문으로 시크릿을 관리할 수 있습니다. 
이 파일들은 `.gitignore`에 포함되어 Git에 커밋되지 않습니다.

```bash
# values/postgresql.yaml에 직접 수정
auth:
  username: application
  password: application
```

### 방법 2: SOPS + Age (암호화, 권장)

로컬에서도 암호화하여 관리하려면 SOPS + Age를 사용하세요.

```bash
# 1. Age 키 생성 및 설정
./k8s-dev-k3d/scripts/setup-sops-age.sh

# 2. 시크릿 파일 생성 및 암호화
cd k8s-dev-k3d/values
cp postgresql.secrets.yaml.example postgresql.secrets.yaml
sops -e postgresql.secrets.yaml > postgresql.secrets.enc.yaml

# 3. Helm 배포 시 암호화된 파일 사용
helm secrets upgrade --install postgresql \
  ../../helm/statefulset-base/postgresql \
  --namespace msa-quality \
  --create-namespace \
  -f postgresql.yaml \
  -f postgresql.secrets.enc.yaml
```

## 📝 사용 방법

### kubeconfig 설정

```bash
export KUBECONFIG=$(pwd)/k8s-dev-k3d/kubeconfig/config
kubectl get nodes
```

### 클러스터 관리

```bash
# 클러스터 목록
k3d cluster list

# 클러스터 시작
k3d cluster start msa-quality-cluster

# 클러스터 중지
k3d cluster stop msa-quality-cluster

# 클러스터 삭제
k3d cluster delete msa-quality-cluster
```

### Helm 차트 배포

```bash
export KUBECONFIG=$(pwd)/k8s-dev-k3d/kubeconfig/config

# Redis 배포 (자동)
cd k8s-dev-k3d/scripts
./start-environment.sh

# 또는 수동 배포 (Redis)
helm upgrade --install redis \
  ../../helm/statefulset-base/redis \
  --namespace msa-quality \
  --create-namespace \
  --values ../values/redis.yaml

# 수동 배포 (PostgreSQL)
helm upgrade --install postgresql \
  ../../helm/statefulset-base/postgresql \
  --namespace msa-quality \
  --create-namespace \
  --values ../values/postgresql.yaml
```

### SOPS로 시크릿 편집

```bash
# 암호화된 파일 직접 편집 (자동 복호화/암호화)
sops k8s-dev-k3d/values/postgresql.secrets.enc.yaml

# 또는 평문 파일 편집 후 재암호화
vi k8s-dev-k3d/values/postgresql.secrets.yaml
sops -e k8s-dev-k3d/values/postgresql.secrets.yaml > k8s-dev-k3d/values/postgresql.secrets.enc.yaml
```

## 🔧 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `CLUSTER_NAME` | `msa-quality-cluster` | k3d 클러스터 이름 |
| `NAMESPACE` | `msa-quality` | Kubernetes 네임스페이스 |
| `NODEPORT_START` | `30000` | NodePort 시작 포트 |
| `NODEPORT_END` | `30100` | NodePort 종료 포트 |
| `WAIT_TIMEOUT` | `600` | Helm 배포 대기 시간 (초) |

## 🏗️ 구조 설명

### Helm 베이스 차트 사용

k3d 환경은 저장소의 Helm 베이스 차트를 직접 사용합니다:

- `helm/statefulset-base/redis/` - Redis Statefulset 베이스 차트
- `helm/statefulset-base/postgresql/` - PostgreSQL Statefulset 베이스 차트
- `helm/management-base/airflow/` - (선택) Airflow 관리용 베이스 차트
- `k8s-dev-k3d/values/*.yaml` - 로컬 환경 최적화 values 파일

### k8s-deployments와의 차이

- **k8s-deployments**: 프로덕션/실단계 배포용 (별도 관리)
- **k8s-dev-k3d**: 로컬 개발/테스트 환경 전용
- **helm/**: 공통 Helm 차트 (양쪽에서 사용)

## 🔒 시크릿 관리 비교

| 방법 | 장점 | 단점 | 사용 시나리오 |
|------|------|------|------------|
| **평문 관리** | 간단, 빠름 | Git에 커밋 불가 | 로컬 개발만 |
| **SOPS + Age** | 암호화, Git에 커밋 가능 | 설정 필요 | 로컬 + 팀 협업 |

## 🐛 문제 해결

### 포트 충돌

```bash
# 포트 사용 확인
lsof -i :80
lsof -i :443
lsof -i :6443

# 포트 범위 변경
export NODEPORT_START=30100
export NODEPORT_END=30200
./install-k3s.sh
```

### 클러스터 재생성

```bash
# 방법 1: 정리 스크립트 사용 (권장)
cd k8s-dev-k3d/scripts
./cleanup.sh

# 방법 2: 수동 삭제
k3d cluster delete msa-quality-cluster
./install-k3s.sh

# 방법 3: 강제 정리 (확인 없이)
cd k8s-dev-k3d/scripts
./cleanup.sh --force
```

### SOPS Age 키 문제

```bash
# Age 키 확인
cat ~/.config/sops/age/keys.txt

# .sops.yaml의 Age 공개 키 확인
grep "age:" .sops.yaml

# Age 키 재생성
./k8s-dev-k3d/scripts/setup-sops-age.sh
```

## 📚 참고 자료

- [k3d 공식 문서](https://k3d.io/)
- [k3s 공식 문서](https://k3s.io/)
- [Helm 공식 문서](https://helm.sh/docs/)
- [SOPS 공식 문서](https://github.com/mozilla/sops)
- [Age 공식 문서](https://github.com/FiloSottile/age)
- [시크릿 관리 가이드](../docs/secrets-management-eks.md)
