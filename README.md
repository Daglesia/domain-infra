kubectl -n argocd create secret generic sops-age \
  --from-file=age.key

age-keygen -o age.key

kubectl patch deployment argocd-repo-server -n argocd \
  --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/volumes/-",
      "value": {
        "name": "sops-age",
        "secret": { "secretName": "sops-age" }
      }
    },
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/volumeMounts/-",
      "value": {
        "name": "sops-age",
        "mountPath": "/etc/sops",
        "readOnly": true
      }
    },
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/env/-",
      "value": {
        "name": "SOPS_AGE_KEY_FILE",
        "value": "/etc/sops/age.key"
      }
    }
  ]'
