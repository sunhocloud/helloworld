# Helm Charts 사용 가이드

## 📋 개요

이 디렉토리에는 K8s 환경에서 사용할 수 있는 Helm 차트들이 포함되어 있습니다.

## 🗂️ 디렉토리 구조

```
helm/
├── management-base/
│   └── airflow/           # Apache Airflow 공통 베이스
├── statefulset-base/
│   ├── postgresql/        # PostgreSQL (Primary-Replica)
│   └── redis/             # Redis Statefulset
├── services/
│   └── customer-service/  # Customer Service
└── test-infrastructure/   # 테스트용 인프라
```

## 🚀 사용 방법

### 1. Dependencies 빌드 (필수)

차트들은 Bitnami의 PostgreSQL과 Redis를 의존성으로 사용합니다. 배포하기 전에 반드시 dependencies를 빌드해야 합니다.

```bash
cd c4ang-infra/helm
./build-dependencies.sh
```

또는 개별적으로:

```bash
# Airflow base (필요 시)
cd management-base/airflow
helm dependency build

# PostgreSQL
cd ../../statefulset-base/postgresql
helm dependency build

# Redis
cd ../redis
helm dependency build

# Test Infrastructure
cd ../../test-infrastructure
helm dependency build
```

### 2. 로컬 Kubernetes (Docker Desktop)에 배포

#### Test Infrastructure 배포

```bash
helm install test-infra ./test-infrastructure \
  --namespace test \
  --create-namespace \
  --wait
```

#### 특정 값 오버라이드

```bash
helm install test-infra ./test-infrastructure \
  --namespace test \
  --create-namespace \
  --set postgresql.auth.database=my_db \
  --set postgresql.auth.username=myuser \
  --set postgresql.auth.password=mypass \
  --wait
```

#### Values 파일 사용

```bash
# custom-values.yaml 생성
cat > custom-values.yaml <<EOF
postgresql:
  auth:
    database: customer_db
    username: testuser
    password: testpass
EOF

helm install test-infra ./test-infrastructure \
  --namespace test \
  --create-namespace \
  --values custom-values.yaml \
  --wait
```

### 3. 배포 확인

```bash
# Helm releases 확인
helm list -n test

# Pod 상태 확인
kubectl get pods -n test

# Service 확인
kubectl get svc -n test

# 로그 확인
kubectl logs -n test <pod-name>
```

### 4. 제거

```bash
# Helm release 제거
helm uninstall test-infra -n test

# Namespace 제거
kubectl delete namespace test
```

## 🧪 Testcontainers K3s에서 사용

테스트 코드에서 사용하는 방법:

```kotlin
@K8sIntegrationTest
class MyK8sTest {
    companion object {
        @BeforeAll
        @JvmStatic
        fun setup() {
            // 네임스페이스 생성
            K8sHelmHelper.createNamespace("test")

            // Helm 차트 배포
            val success = K8sHelmHelper.installHelmChart(
                chartPath = "../c4ang-infra/helm/test-infrastructure",
                releaseName = "test-infra",
                namespace = "test",
                values = mapOf(
                    "postgresql.auth.database" to "customer_db",
                    "postgresql.auth.username" to "test",
                    "postgresql.auth.password" to "test"
                )
            )

            require(success) { "Failed to install test infrastructure" }
        }
    }
}
```

## 📊 차트별 설정

### PostgreSQL (statefulset-base/postgresql)

기본 설정:
- Primary-Replica 아키텍처
- Replica 개수: 1
- Persistence: 활성화 (10Gi)
- 기본 데이터베이스: groom
- 기본 사용자: application

커스터마이징:

```bash
helm install my-postgres ./statefulset-base/postgresql \
  --set postgresql.auth.database=mydb \
  --set postgresql.readReplicas.replicaCount=2 \
  --set postgresql.primary.persistence.size=20Gi
```

### Redis (statefulset-base/redis)

기본 설정:
- Standalone 모드
- Auth: 비활성화
- Persistence: 활성화 (5Gi)

커스터마이징:

```bash
helm install my-redis ./statefulset-base/redis \
  --set redis.auth.enabled=true \
  --set redis.auth.password=mypassword \
  --set redis.master.persistence.size=10Gi
```

### Test Infrastructure

테스트용 최적화:
- Persistence: 비활성화 (빠른 시작)
- 최소 리소스 사용
- PostgreSQL + Redis 포함

```bash
helm install test-infra ./test-infrastructure \
  --namespace test \
  --create-namespace
```

## 🔧 트러블슈팅

### Dependencies 오류

```
Error: found in Chart.yaml, but missing in charts/ directory
```

**해결방법:** `helm dependency build` 실행

### ImagePullBackOff

```
Failed to pull image "bitnami/postgresql:17"
```

**해결방법:**
1. 인터넷 연결 확인
2. Docker Hub rate limit 확인
3. 이미지 태그 확인

### Pending Pods

```
pod "test-infra-postgresql-0" is pending
```

**해결방법:**
1. PVC 상태 확인: `kubectl get pvc -n test`
2. 스토리지 클래스 확인: `kubectl get sc`
3. 리소스 부족 확인: `kubectl describe pod <pod-name> -n test`

## 📚 참고 자료

- [Helm Documentation](https://helm.sh/docs/)
- [Bitnami PostgreSQL Chart](https://github.com/bitnami/charts/tree/main/bitnami/postgresql)
- [Bitnami Redis Chart](https://github.com/bitnami/charts/tree/main/bitnami/redis)
- [Testcontainers K3s Module](https://java.testcontainers.org/modules/k3s/)
