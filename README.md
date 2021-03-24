# zero-touch-assisted-operator

This repository will walk through the required steps for deploying OpenShift with zero touch provisioning. It utilizes the Assisted Installer Operator. The steps followed here include the compiled operator and installation steps provided by @jparrill.

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
    app: assisted-service 
  name: bucket-pv-claim 
  namespace: assisted-installer
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: assisted-service
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/jparrill/assisted-service-index:0.0.1
EOF
  ```
  
Next, add the subscription for the new CatalogSource

```
cat <<EOF | oc create -f -
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: assisted-installer-operator
  namespace: assisted-installer
spec:
  targetNamespaces:
  - assisted-installer
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: assisted-service-operator
  namespace: assisted-installer 
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: assisted-service-operator
  source: assisted-service
  sourceNamespace: openshift-marketplace
  startingCSV: assisted-service-operator.v0.0.1
  config:
    env:
    - name: DEPLOY_TARGET
      value: "onprem"
EOF
```
Note: the onprem deployment target bypasses the baremetal inventory check on the cluster hosting Assisted installer

## Creating the new Custom Resources for OpenShift Deployment

The CR install process requires 4 objects for deployment.
1. The pull secret for the image
2. An SSH private key for manipulation of the deployed node via Hive.
3. The ClusterDeployment manifest which specifies the OCP version to be deployed and other information that would typically be defined in the install-config.
4. The InstallEnv this kicks off the creation of the discovery ISO and is what you will boot the node to. 




