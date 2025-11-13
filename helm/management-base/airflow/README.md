# airflow-base Chart

Apache Airflow 공식 Helm Chart(`apache-airflow/airflow`)을 래핑하여 조직 표준 설정을 제공하는 공통 Chart입니다.

## 구조

- `Chart.yaml`: Airflow 공식 Chart를 의존성으로 선언
- `values.yaml`: 공통 기본 설정 (CeleryExecutor, PVC 바인딩 등)
- `templates/`: 추가 리소스 템플릿이 필요한 경우 확장용 (현재 비어 있음)

## 사용법

```bash
helm dependency update platform-charts/charts/airflow-base
helm template airflow platform-charts/charts/airflow-base \
  -f k8s-deployments/infrastructure/airflow/base/values.yaml
```

## 의존성

- Apache Airflow Helm Chart `>=1.13.0`

## 참고

- https://airflow.apache.org/docs/helm-chart/stable/index.html
