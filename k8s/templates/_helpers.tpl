{{/*
Helpers reutilizáveis para nomeação de recursos do chart.
*/}}

{{- define "guess-game.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "guess-game.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Rótulos (labels) comuns aplicados a todos os recursos.
*/}}
{{- define "guess-game.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: guess-game
{{- end -}}

{{/* Seletor de pods por componente (backend, frontend, postgres). */}}
{{- define "guess-game.selectorLabels" -}}
app.kubernetes.io/name: {{ include "guess-game.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
