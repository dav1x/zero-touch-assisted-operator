# zero-touch-assisted-operator

This repository will walk through the required steps for deploying OpenShift with zero touch provisioning. It utilizes the Assisted Installer Operator. The steps followed here including the compiled operator were provided by @jparrill.

## Deploying the Operator

The deployment requires persistent storage. This following example uses the default storage class in the OCP cluster
```
cat <<EOF | oc create -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: assisted-installer
  labels:
    name: assisted-installer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app: postgres
  name: postgres-pv-claim
  namespace: assisted-installer
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app: scality
  name: scality-pv-claim
  namespace: assisted-installer
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: assisted-service
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/jparrill/assisted-service-index:0.0.1
  ```
