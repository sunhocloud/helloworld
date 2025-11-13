{{/*
Expand the name of the chart.
*/}}
{{- define "redis-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "redis-chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "redis-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "redis-chart.labels" -}}
helm.sh/chart: {{ include "redis-chart.chart" . }}
{{ include "redis-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.global.partOf | default "review-analysis-system" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redis-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Redis Master labels
*/}}
{{- define "redis-chart.masterLabels" -}}
{{ include "redis-chart.labels" . }}
app: {{ .Values.global.appName }}
component: master
app.kubernetes.io/component: master
{{- end }}

{{/*
Redis Slave labels
*/}}
{{- define "redis-chart.slaveLabels" -}}
{{ include "redis-chart.labels" . }}
app: {{ .Values.global.appName }}
component: slave
app.kubernetes.io/component: slave
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "redis-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "redis-chart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "redis-chart.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace }}
{{- end }}

{{/*
Redis Master FQDN
*/}}
{{- define "redis-chart.masterFQDN" -}}
{{- printf "%s-master-0.%s-master.%s.svc.cluster.local" (include "redis-chart.fullname" .) (include "redis-chart.fullname" .) (include "redis-chart.namespace" .) }}
{{- end }}

{{/*
Redis Master Service Name
*/}}
{{- define "redis-chart.masterServiceName" -}}
{{- printf "%s-master" (include "redis-chart.fullname" .) }}
{{- end }}

{{/*
Redis Slave Service Name
*/}}
{{- define "redis-chart.slaveServiceName" -}}
{{- printf "%s-slave" (include "redis-chart.fullname" .) }}
{{- end }}

{{/*
Redis Secret Name
*/}}
{{- define "redis-chart.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "redis-chart.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Redis ConfigMap Name
*/}}
{{- define "redis-chart.configMapName" -}}
{{- printf "%s-config" (include "redis-chart.fullname" .) }}
{{- end }}

{{/*
Redis Scripts ConfigMap Name
*/}}
{{- define "redis-chart.scriptsConfigMapName" -}}
{{- printf "%s-scripts" (include "redis-chart.fullname" .) }}
{{- end }}

{{/*
Generate Redis password
*/}}
{{- define "redis-chart.password" -}}
{{- if .Values.auth.password }}
{{- .Values.auth.password }}
{{- else if .Values.auth.existingSecret }}
{{- "" }}
{{- else }}
{{- randAlphaNum 24 }}
{{- end }}
{{- end }}

