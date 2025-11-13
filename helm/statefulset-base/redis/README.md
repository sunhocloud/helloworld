# Redis Base Library Chart

Redis Master-Slave 클러스터를 위한 **Library Chart**입니다.

## 📌 Library Chart란?

Library Chart는 **재사용 가능한 템플릿**을 제공합니다. 직접 배포되지 않고, 다른 차트나 배포 설정에서 사용됩니다.

## 🎯 사용 목적

- ✅ **표준화**: 모든 환경에서 동일한 Redis 템플릿 사용
- ✅ **재사용성**: 여러 환경(dev/staging/prod)에서 동일한 차트 재사용
- ✅ **관심사 분리**: 템플릿(HOW)과 설정(WHAT) 분리

## 📁 구조

```
helm/statefulset-base/redis/
├── Chart.yaml          # type: library
├── values.yaml         # 안전한 기본값만
└── templates/         # Kubernetes 리소스 템플릿
```

## ⚠️ 주의사항

- 이 차트는 **직접 설치하지 않습니다**
- `helm/services/*` 혹은 오버레이 차트에서 의존성으로 추가해 사용
- ArgoCD, Helm CLI 등 원하는 배포 방식에 맞춰 조합

## 📚 관련 문서

- 로컬 k3d 예시: `k8s-dev-k3d/values/redis.yaml`
- 공용 Helm 사용법: `helm/README.md`

