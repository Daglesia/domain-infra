{{- define "jellyfin.pvName" -}}
  jellyfin-media-pv
{{- end }}

{{- define "jellyfin.pvcName" -}}
  jellyfin-media-pvc
{{- end }}

{{- define "jellyfin.storageSize" -}}
  25Gi
{{- end }}

{{- define "jellyfin.nodeSelectorTermsConfig" -}}
  matchExpressions:
    - key: kubernetes.io/hostname
      operator: In
      values:
        - raspberka-ekran
{{- end }}