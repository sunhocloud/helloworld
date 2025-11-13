# Makefile for C4ang Infrastructure
# 개발자 친화적인 로컬 환경 관리 인터페이스

.PHONY: help local-up local-down local-clean local-restart local-status
.PHONY: install-tools helm-deps helm-build
.PHONY: istio-install istio-uninstall istio-status
.PHONY: k3d-create k3d-start k3d-stop k3d-delete k3d-list
.PHONY: kubectl-config kubectl-ns kubectl-pods kubectl-svc
.PHONY: sops-setup sops-encrypt sops-decrypt
.PHONY: eks-deploy-airflow eks-install-istio
.DEFAULT_GOAL := help

# 색상 정의
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
RED    := \033[0;31m
NC     := \033[0m

# 설정 변수
CLUSTER_NAME ?= msa-quality-cluster
NAMESPACE ?= msa-quality
KUBECONFIG_PATH := $(CURDIR)/k8s-dev-k3d/kubeconfig/config

# Help 명령어 - 모든 타겟과 설명을 보여줌
help: ## 사용 가능한 명령어 표시
	@echo "$(BLUE)C4ang Infrastructure - 로컬 개발 환경 관리$(NC)"
	@echo ""
	@echo "$(GREEN)사용법:$(NC)"
	@echo "  make <target>"
	@echo ""
	@echo "$(GREEN)주요 명령어:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-25s$(NC) %s\n", $$1, $$2}' | \
		sort
	@echo ""
	@echo "$(GREEN)환경 변수:$(NC)"
	@echo "  CLUSTER_NAME=$(CLUSTER_NAME)"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  KUBECONFIG_PATH=$(KUBECONFIG_PATH)"

##@ 로컬 환경 관리 (k3d)

local-up: install-tools helm-deps k3d-create ## 로컬 k3d 환경 완전 시작 (도구 설치 + 클러스터 생성 + Helm 배포)
	@echo "$(BLUE)🚀 로컬 환경 시작 중...$(NC)"
	@cd k8s-dev-k3d/scripts && ./start-environment.sh
	@echo ""
	@echo "$(GREEN)✅ 로컬 환경이 준비되었습니다!$(NC)"
	@echo ""
	@echo "$(YELLOW)📋 다음 명령으로 kubectl을 사용하세요:$(NC)"
	@echo "  export KUBECONFIG=$(KUBECONFIG_PATH)"
	@echo ""
	@echo "$(YELLOW)📊 상태 확인:$(NC)"
	@echo "  make local-status"

local-down: ## 로컬 환경 중지 (데이터 유지)
	@echo "$(BLUE)⏸️  로컬 환경 중지 중...$(NC)"
	@cd k8s-dev-k3d/scripts && ./stop-environment.sh
	@echo "$(GREEN)✅ 로컬 환경이 중지되었습니다$(NC)"

local-clean: ## 로컬 환경 완전 제거 (클러스터 삭제)
	@echo "$(RED)🗑️  로컬 환경 완전 제거 중...$(NC)"
	@cd k8s-dev-k3d/scripts && ./cleanup.sh --force
	@echo "$(GREEN)✅ 로컬 환경이 제거되었습니다$(NC)"

local-restart: local-down local-up ## 로컬 환경 재시작

local-status: ## 로컬 환경 상태 확인
	@echo "$(BLUE)📊 로컬 환경 상태:$(NC)"
	@echo ""
	@echo "$(YELLOW)k3d 클러스터:$(NC)"
	@k3d cluster list 2>/dev/null || echo "  k3d가 설치되지 않았거나 클러스터가 없습니다"
	@echo ""
	@echo "$(YELLOW)Kubernetes 노드:$(NC)"
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get nodes 2>/dev/null || echo "  클러스터가 실행 중이지 않습니다"
	@echo ""
	@echo "$(YELLOW)Pods (네임스페이스: $(NAMESPACE)):$(NC)"
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "  네임스페이스가 존재하지 않거나 Pod가 없습니다"
	@echo ""
	@echo "$(YELLOW)Services (네임스페이스: $(NAMESPACE)):$(NC)"
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get svc -n $(NAMESPACE) 2>/dev/null || echo "  서비스가 없습니다"

##@ 도구 설치 및 설정

install-tools: ## 필수 도구 설치 (k3d, helm, kubectl)
	@echo "$(BLUE)🔧 필수 도구 설치 확인 중...$(NC)"
	@cd k8s-dev-k3d && ./install-k3s.sh
	@echo "$(GREEN)✅ 필수 도구 확인 완료$(NC)"

helm-deps: helm-build ## Helm 차트 의존성 빌드 (alias for helm-build)

helm-build: ## Helm 차트 의존성 빌드
	@echo "$(BLUE)📦 Helm 의존성 빌드 중...$(NC)"
	@if [ -f helm/build-dependencies.sh ]; then \
		cd helm && ./build-dependencies.sh; \
	else \
		echo "$(YELLOW)⚠️  helm/build-dependencies.sh가 없습니다. 수동으로 빌드합니다...$(NC)"; \
		for chart_dir in helm/statefulset-base/* helm/management-base/* helm/test-infrastructure; do \
			if [ -f "$$chart_dir/Chart.yaml" ]; then \
				echo "  Building $$chart_dir..."; \
				cd "$$chart_dir" && helm dependency build && cd - > /dev/null; \
			fi; \
		done; \
	fi
	@echo "$(GREEN)✅ Helm 의존성 빌드 완료$(NC)"

##@ k3d 클러스터 관리

k3d-create: ## k3d 클러스터만 생성 (Helm 배포 제외)
	@echo "$(BLUE)🏗️  k3d 클러스터 생성 중...$(NC)"
	@cd k8s-dev-k3d && ./install-k3s.sh
	@echo "$(GREEN)✅ k3d 클러스터 생성 완료$(NC)"

k3d-start: ## k3d 클러스터 시작
	@echo "$(BLUE)▶️  k3d 클러스터 시작 중...$(NC)"
	@k3d cluster start $(CLUSTER_NAME)
	@echo "$(GREEN)✅ 클러스터가 시작되었습니다$(NC)"

k3d-stop: ## k3d 클러스터 중지
	@echo "$(BLUE)⏹️  k3d 클러스터 중지 중...$(NC)"
	@k3d cluster stop $(CLUSTER_NAME)
	@echo "$(GREEN)✅ 클러스터가 중지되었습니다$(NC)"

k3d-delete: ## k3d 클러스터 삭제
	@echo "$(RED)🗑️  k3d 클러스터 삭제 중...$(NC)"
	@k3d cluster delete $(CLUSTER_NAME)
	@echo "$(GREEN)✅ 클러스터가 삭제되었습니다$(NC)"

k3d-list: ## k3d 클러스터 목록 표시
	@echo "$(BLUE)📋 k3d 클러스터 목록:$(NC)"
	@k3d cluster list

##@ Istio 서비스 메시

istio-install: ## Istio 설치 (로컬 k3d 환경)
	@echo "$(BLUE)🕸️  Istio 설치 중...$(NC)"
	@cd k8s-dev-k3d/istio && ./install-istio.sh
	@echo "$(GREEN)✅ Istio 설치 완료$(NC)"

istio-uninstall: ## Istio 제거 (로컬 k3d 환경)
	@echo "$(BLUE)🗑️  Istio 제거 중...$(NC)"
	@cd k8s-dev-k3d/istio && ./uninstall-istio.sh
	@echo "$(GREEN)✅ Istio 제거 완료$(NC)"

istio-status: ## Istio 상태 확인
	@echo "$(BLUE)📊 Istio 상태:$(NC)"
	@echo ""
	@echo "$(YELLOW)Istio System Pods:$(NC)"
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get pods -n istio-system 2>/dev/null || echo "  Istio가 설치되지 않았습니다"
	@echo ""
	@echo "$(YELLOW)Gateway:$(NC)"
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get gateway -n $(NAMESPACE) 2>/dev/null || echo "  Gateway가 없습니다"
	@echo ""
	@echo "$(YELLOW)HTTPRoute:$(NC)"
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get httproute -n $(NAMESPACE) 2>/dev/null || echo "  HTTPRoute가 없습니다"

##@ kubectl 유틸리티

kubectl-config: ## kubectl 설정 정보 출력
	@echo "$(BLUE)⚙️  kubectl 설정:$(NC)"
	@echo ""
	@echo "$(YELLOW)KUBECONFIG 경로:$(NC)"
	@echo "  $(KUBECONFIG_PATH)"
	@echo ""
	@echo "$(YELLOW)다음 명령으로 환경 변수를 설정하세요:$(NC)"
	@echo "  export KUBECONFIG=$(KUBECONFIG_PATH)"
	@echo ""
	@echo "$(YELLOW)또는 직접 사용:$(NC)"
	@echo "  kubectl --kubeconfig=$(KUBECONFIG_PATH) get nodes"

kubectl-ns: ## 모든 네임스페이스 목록
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get namespaces

kubectl-pods: ## 모든 Pods 목록 (네임스페이스: $(NAMESPACE))
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get pods -n $(NAMESPACE)

kubectl-svc: ## 모든 Services 목록 (네임스페이스: $(NAMESPACE))
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get svc -n $(NAMESPACE)

##@ SOPS 시크릿 관리

sops-setup: ## SOPS Age 키 설정 (로컬 환경용)
	@echo "$(BLUE)🔐 SOPS Age 키 설정 중...$(NC)"
	@cd k8s-dev-k3d/scripts && ./setup-sops-age.sh
	@echo "$(GREEN)✅ SOPS Age 키 설정 완료$(NC)"

sops-encrypt: ## SOPS로 시크릿 파일 암호화 (사용법: make sops-encrypt FILE=path/to/secrets.yaml)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)❌ 오류: FILE 변수가 필요합니다$(NC)"; \
		echo "사용법: make sops-encrypt FILE=path/to/secrets.yaml"; \
		exit 1; \
	fi
	@echo "$(BLUE)🔐 파일 암호화 중: $(FILE)$(NC)"
	@sops -e "$(FILE)" > "$(FILE).enc.yaml"
	@echo "$(GREEN)✅ 암호화 완료: $(FILE).enc.yaml$(NC)"

sops-decrypt: ## SOPS로 시크릿 파일 복호화 (사용법: make sops-decrypt FILE=path/to/secrets.enc.yaml)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)❌ 오류: FILE 변수가 필요합니다$(NC)"; \
		echo "사용법: make sops-decrypt FILE=path/to/secrets.enc.yaml"; \
		exit 1; \
	fi
	@echo "$(BLUE)🔓 파일 복호화 중: $(FILE)$(NC)"
	@sops -d "$(FILE)"

##@ EKS 환경 배포

eks-deploy-airflow: ## EKS에 Airflow 배포
	@echo "$(BLUE)☁️  EKS에 Airflow 배포 중...$(NC)"
	@cd k8s-eks/scripts && ./deploy-airflow.sh
	@echo "$(GREEN)✅ Airflow 배포 완료$(NC)"

eks-install-istio: ## EKS에 Istio 설치
	@echo "$(BLUE)☁️  EKS에 Istio 설치 중...$(NC)"
	@cd k8s-eks/istio && ./install-istio.sh
	@echo "$(GREEN)✅ Istio 설치 완료$(NC)"

##@ 기타

clean-helm-cache: ## Helm 캐시 정리
	@echo "$(BLUE)🧹 Helm 캐시 정리 중...$(NC)"
	@find helm -type f -name "*.tgz" -delete
	@find helm -type d -name "charts" -exec rm -rf {} + 2>/dev/null || true
	@echo "$(GREEN)✅ Helm 캐시 정리 완료$(NC)"

version: ## 설치된 도구 버전 표시
	@echo "$(BLUE)📋 설치된 도구 버전:$(NC)"
	@echo ""
	@echo "$(YELLOW)k3d:$(NC)"
	@k3d version 2>/dev/null || echo "  설치되지 않음"
	@echo ""
	@echo "$(YELLOW)kubectl:$(NC)"
	@kubectl version --client --short 2>/dev/null || echo "  설치되지 않음"
	@echo ""
	@echo "$(YELLOW)helm:$(NC)"
	@helm version --short 2>/dev/null || echo "  설치되지 않음"
	@echo ""
	@echo "$(YELLOW)docker:$(NC)"
	@docker version --format '{{.Client.Version}}' 2>/dev/null || echo "  설치되지 않음"
	@echo ""
	@echo "$(YELLOW)sops:$(NC)"
	@sops --version 2>/dev/null || echo "  설치되지 않음"
