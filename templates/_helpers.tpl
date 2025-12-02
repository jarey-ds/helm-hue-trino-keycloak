{{/*
Expand the name of the chart.
*/}}
{{- define "trino-hue.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "trino-hue.fullname" -}}
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
Generate Trino service name for Hue
*/}}
{{- define "trino-hue.trinoServiceName" -}}
{{- if .Values.hue.trino.serviceName }}
{{- .Values.hue.trino.serviceName }}
{{- else }}
{{- printf "%s-trino" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Generate Trino interpreter configuration for Hue
*/}}
{{- define "trino-hue.trinoInterpreter" -}}
[[[trino]]]
name=Trino
interface=trino
options='{"url": "http://{{ include "trino-hue.trinoServiceName" . }}:{{ .Values.hue.trino.port }}", "auth_username": "{{ .Values.hue.trino.auth_username }}", "auth_password": "{{ .Values.hue.trino.auth_password }}"}'
{{- end }}

{{/*
Generate complete interpreters configuration for Hue
*/}}
{{- define "trino-hue.hueInterpreters" -}}
{{- if .Values.hue.interpreters }}
{{- $trinoInterpreter := include "trino-hue.trinoInterpreter" . }}
{{- $existingInterpreters := .Values.hue.interpreters }}
{{- if contains "[[[trino]]]" $existingInterpreters }}
{{- $existingInterpreters | replace "RELEASE_NAME-trino" (include "trino-hue.trinoServiceName" .) }}
{{- else }}
{{- $trinoInterpreter }}
{{- if $existingInterpreters }}
{{- $existingInterpreters }}
{{- end }}
{{- end }}
{{- else }}
{{- include "trino-hue.trinoInterpreter" . }}
{{- end }}
{{- end }}

