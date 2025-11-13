# C4ang Infrastructure Configuration

MSA 전환을 위한 공통 인프라 설정 저장소입니다.

## 📁 디렉토리 구조

```
c4ang-infra/
├── docker-compose/
│   ├── base/
│   │   └── docker-compose.base.yml         # Redis, Kafka 등 공통 인프라
│   ├── postgres/
│   │   └── docker-compose.postgres.yml     # PostgreSQL Primary + Replica 템플릿
│   └── test/
│       └── docker-compose-integration-test.yml  # 통합 테스트용
├── docker/
│   └── postgres/
│       ├── primary-init/                   # Primary DB 초기화 스크립트
│       └── replica-init/                   # Replica DB 초기화 스크립트
└── testcontainers/
    └── kotlin/
        ├── BaseContainerExtension.kt       # 통합 테스트 Base Extension
        └── IntegrationTest.kt              # 통합 테스트 어노테이션
```

## 🚀 빠른 시작 (Makefile 사용)

### Makefile로 간편하게 로컬 환경 구축

```bash
# 1. 모든 명령어 확인
make help

# 2. 로컬 k3d 환경 한 번에 시작 (도구 설치 + 클러스터 생성 + Helm 배포)
make local-up

# 3. KUBECONFIG 설정
export KUBECONFIG=$(pwd)/k8s-dev-k3d/kubeconfig/config

# 4. 상태 확인
make local-status

# 5. 환경 중지
make local-down

# 6. 환경 완전 제거
make local-clean
```

**주요 Makefile 명령어:**
- `make local-up` - 로컬 환경 완전 시작
- `make local-status` - 현재 상태 확인
- `make local-down` - 환경 중지
- `make local-clean` - 환경 완전 제거
- `make istio-install` - Istio 설치
- `make version` - 설치된 도구 버전 확인
- `make help` - 모든 명령어 보기

---

## 📚 사용 방법 (상세)

### 1. 서브모듈로 추가

각 도메인 서비스 레포지토리에서:

```bash
git submodule add git@github.com:GroomC4/c4ang-infra.git infra-config
git submodule update --init --recursive
```

### 2. 개발 환경 Docker Compose 설정

**docker-compose-dev.yml** (각 서비스 레포지토리 루트):

```yaml
# Store Service 예시
services:
  postgres-primary:
    extends:
      file: ./infra-config/docker-compose/postgres/docker-compose.postgres.yml
      service: postgres-primary
    environment:
      POSTGRES_DB: store_db
      SCHEMA_PATH: ./sql/store_schema.sql
    volumes:
      - ./sql/store_schema.sql:/docker-entrypoint-initdb.d/010_schema.sql:ro

  redis:
    extends:
      file: ./infra-config/docker-compose/base/docker-compose.base.yml
      service: redis
```

실행:
```bash
INFRA_CONFIG_PATH=./infra-config docker-compose -f docker-compose-dev.yml up
```

### 3. 통합 테스트 설정

**build.gradle.kts**:
```kotlin
sourceSets {
    test {
        kotlin {
            srcDir("infra-config/testcontainers/kotlin")
        }
    }
}
```

**StoreServiceContainerExtension.kt** (각 서비스의 test 디렉토리):
```kotlin
package com.groom.store.common.extension

import com.groom.infra.testcontainers.BaseContainerExtension
import java.io.File

class StoreServiceContainerExtension : BaseContainerExtension() {
    override fun getComposeFile(): File {
        return resolveComposeFile("infra-config/docker-compose/test/docker-compose-integration-test.yml")
    }

    override fun getSchemaFile(): File {
        return resolveComposeFile("sql/store_schema.sql")
    }
}
```

**IntegrationTest.kt** (각 서비스의 test 디렉토리):
```kotlin
package com.groom.store.common.annotation

import com.groom.infra.testcontainers.IntegrationTest as BaseIntegrationTest
import com.groom.store.common.extension.StoreServiceContainerExtension
import org.junit.jupiter.api.extension.ExtendWith
import org.springframework.boot.test.context.SpringBootTest

@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
@BaseIntegrationTest
@SpringBootTest
@ExtendWith(StoreServiceContainerExtension::class)
annotation class IntegrationTest
```

**테스트 코드**:
```kotlin
@IntegrationTest
@AutoConfigureMockMvc
class StoreControllerIntegrationTest {
    @Test
    fun `통합 테스트`() {
        // BaseContainerExtension의 메서드 사용 가능
        val jdbcUrl = BaseContainerExtension.getPrimaryJdbcUrl()
        // 테스트 로직
    }
}
```

### 4. 환경 변수

**필수 환경 변수**:
- `INFRA_CONFIG_PATH`: c4ang-infra 디렉토리 경로 (기본값: `.`)
- `SCHEMA_PATH`: 스키마 파일 경로 (각 서비스별로 다름)

**선택 환경 변수** (docker-compose.postgres.yml):
- `PRIMARY_POSTGRES_USER`: Primary DB 사용자 (기본값: `application`)
- `PRIMARY_POSTGRES_PASSWORD`: Primary DB 비밀번호 (기본값: `application`)
- `PRIMARY_POSTGRES_DB`: Primary DB 이름 (기본값: `groom`)
- `PRIMARY_POSTGRES_PORT`: Primary DB 포트 (기본값: `15432`)
- `REPLICA_POSTGRES_PORT`: Replica DB 포트 (기본값: `15433`)

## 📦 서비스별 스키마 관리

각 서비스는 독립적인 스키마 파일을 관리합니다:

```
ecommerce-store-service/
├── infra-config/  (서브모듈)
├── sql/
│   └── store_schema.sql        # Store 도메인 테이블만
├── docker-compose-dev.yml
└── src/test/
    └── resources/
        └── docker-compose-test.yml  (optional)
```

## 🔄 서브모듈 업데이트

인프라 설정이 변경되었을 때:

```bash
cd infra-config
git pull origin main
cd ..
git add infra-config
git commit -m "chore: Update infra-config"
```

## 🎯 향후 계획

- [ ] Helm Charts 추가 (K8s 배포용)
- [ ] Testcontainers K3s Module 지원
- [ ] Kafka, RabbitMQ 등 추가 인프라
- [ ] Monitoring Stack (Prometheus, Grafana)

## 📝 참고 문서

- [Docker Compose 공식 문서](https://docs.docker.com/compose/)
- [Testcontainers 공식 문서](https://www.testcontainers.org/)
- [PostgreSQL Replication](https://www.postgresql.org/docs/current/warm-standby.html)
