{{- define "grist.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "grist.labels" -}}
app.kubernetes.io/name: {{ include "grist.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "grist.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grist.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
