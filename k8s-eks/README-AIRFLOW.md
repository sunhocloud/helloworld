# EKS에 Airflow 배포 가이드

NetApp 문서를 기반으로 EKS 클러스터에 Apache Airflow를 배포하는 가이드입니다.

## 📋 필수 조건

배포를 시작하기 전에 다음 사항을 확인하세요:

1. **작동하는 EKS 클러스터**
   ```bash
   kubectl cluster-info
   ```

2. **NetApp Trident 설치 및 구성** (선택사항)
   - Trident를 사용하는 경우, StorageClass가 올바르게 구성되어 있어야 합니다.
   - Trident 문서: https://netapp-trident.readthedocs.io/

3. **Helm 설치**
   ```bash
   # Helm 설치 확인
   helm version
   
   # 설치되어 있지 않은 경우
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

4. **기본 StorageClass 설정**
   ```bash
   # 현재 기본 StorageClass 확인
   kubectl get storageclass
   
   # 기본 StorageClass가 없는 경우 설정
   # 예: gp2를 기본으로 설정
   kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   ```

## 🚀 배포 방법

### 방법 1: 자동 배포 스크립트 사용 (권장)

```bash
cd k8s-eks
./scripts/deploy-airflow.sh
```

스크립트가 다음을 자동으로 수행합니다:
- 필수 도구 확인
- Kubernetes 연결 확인
- 기본 StorageClass 확인 및 설정
- Helm 차트 의존성 빌드
- Namespace 생성
- Airflow 배포
- 배포 상태 확인 및 접속 정보 출력

### 방법 2: 수동 배포

#### 1. Helm 차트 의존성 빌드

```bash
cd helm/management-base/airflow
helm dependency update
cd ../../..
```

#### 2. Namespace 생성

```bash
kubectl create namespace airflow
```

#### 3. Airflow 배포

```bash
helm install airflow helm/management-base/airflow \
  -n airflow \
  -f k8s-eks/values/airflow.yaml \
  --wait \
  --timeout 10m
```

#### 4. 배포 확인

```bash
# Pod 상태 확인
kubectl get pods -n airflow

# 모든 Pod가 Running 상태가 될 때까지 대기
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=airflow -n airflow --timeout=600s
```

## 🌐 Airflow 접속

### NodePort를 통한 접속

배포가 완료되면 다음 명령으로 접속 URL을 확인할 수 있습니다:

```bash
export NODE_PORT=$(kubectl get --namespace airflow -o jsonpath="{.spec.ports[0].nodePort}" services airflow-web)
export NODE_IP=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='ExternalIP')].address}")
# ExternalIP가 없는 경우 InternalIP 사용
if [ -z "$NODE_IP" ]; then
  export NODE_IP=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='InternalIP')].address}")
fi
echo "Airflow Web UI: http://$NODE_IP:$NODE_PORT"
```

### 기본 로그인 정보

- **Username**: `admin`
- **Password**: `admin`

⚠️ **보안 주의**: 초기 배포 후 반드시 비밀번호를 변경하세요.

## 📊 배포 구성

### 주요 설정

- **Executor**: CeleryExecutor
- **Web Server**: NodePort 서비스 타입
- **Workers**: 2개 레플리카
- **PostgreSQL**: 내장 PostgreSQL 사용
- **Redis**: Celery 브로커로 사용
- **Logs**: 영구 볼륨 사용 (10Gi)
- **DAGs**: 영구 볼륨 사용 (5Gi)
- **Flower**: Celery 모니터링 도구 활성화

### 리소스 요구사항

- **PostgreSQL**: 512Mi-1Gi 메모리, 500m-1000m CPU
- **Redis**: 기본 설정
- **Web Server**: 512Mi-1Gi 메모리, 500m-1000m CPU
- **Scheduler**: 512Mi-1Gi 메모리, 500m-1000m CPU
- **Workers**: 1Gi-2Gi 메모리, 500m-1000m CPU (각)
- **Flower**: 256Mi-512Mi 메모리, 250m-500m CPU

## 🔧 설정 커스터마이징

`k8s-eks/values/airflow.yaml` 파일을 수정하여 설정을 변경할 수 있습니다.

### 예시: Worker 수 증가

```yaml
workers:
  replicas: 4
```

### 예시: Git Sync 활성화

```yaml
dags:
  gitSync:
    enabled: true
    repo: "git@github.com:your-org/airflow-dags.git"
    branch: master
    sshSecret: "airflow-ssh-git-secret"
    sshSecretKey: id_rsa
    syncWait: 60
```

Git Sync를 사용하려면 SSH 키를 포함한 Secret을 먼저 생성해야 합니다:

```bash
kubectl create secret generic airflow-ssh-git-secret \
  --from-file=id_rsa=/path/to/private/key \
  --from-file=id_rsa.pub=/path/to/public/key \
  --from-file=known_hosts=/path/to/known_hosts \
  -n airflow
```

### 예시: Ingress 활성화 (ALB 사용)

```yaml
ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
```

## 🔍 문제 해결

### Pod가 시작되지 않는 경우

```bash
# Pod 이벤트 확인
kubectl describe pod <pod-name> -n airflow

# Pod 로그 확인
kubectl logs <pod-name> -n airflow
```

### PVC가 바인딩되지 않는 경우

```bash
# PVC 상태 확인
kubectl get pvc -n airflow

# StorageClass 확인
kubectl get storageclass
```

### 기본 StorageClass가 없는 경우

```bash
# 사용 가능한 StorageClass 확인
kubectl get storageclass

# 기본 StorageClass로 설정 (예: gp2)
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Airflow 웹 UI에 접속할 수 없는 경우

```bash
# 서비스 확인
kubectl get svc -n airflow

# NodePort 확인
kubectl get svc airflow-web -n airflow -o yaml

# 방화벽 규칙 확인 (보안 그룹)
# EKS 노드의 보안 그룹에서 NodePort 범위(30000-32767)를 열어야 합니다.
```

## 📝 업그레이드

```bash
cd helm/management-base/airflow
helm dependency update
cd ../../..

helm upgrade airflow helm/management-base/airflow \
  -n airflow \
  -f k8s-eks/values/airflow.yaml \
  --wait \
  --timeout 10m
```

## 🗑️ 삭제

```bash
# Helm 릴리스 삭제
helm uninstall airflow -n airflow

# Namespace 삭제 (모든 리소스 포함)
kubectl delete namespace airflow

# PVC는 기본적으로 유지됩니다. 완전히 삭제하려면:
kubectl delete pvc -n airflow --all
```

## 📚 참고 자료

- [NetApp MLOps 문서](https://docs.netapp.com/us-en/netapp-solutions/ai/ai-mlops-airflow.html)
- [Apache Airflow Helm Chart](https://airflow.apache.org/docs/helm-chart/stable/index.html)
- [Apache Airflow 공식 문서](https://airflow.apache.org/docs/)

## 🆘 지원

문제가 발생하면 다음을 확인하세요:

1. Pod 로그: `kubectl logs <pod-name> -n airflow`
2. 이벤트: `kubectl get events -n airflow --sort-by='.lastTimestamp'`
3. 리소스 상태: `kubectl get all -n airflow`


