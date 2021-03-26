# zero-touch-assisted-operator

This repository will walk through the required steps for deploying OpenShift with zero touch provisioning. It utilizes the Assisted Installer Operator. The steps followed here include the compiled operator and installation steps provided by @jparrill. The operator uses the ClusterDeployment `CRD` provided by Hive. But, it requires hive from ocm-2.3 or higher. Lower versions will not include the 

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

Now that the pods are online, edit the appropriate ConfigMaps and restart pods to allow for a single node openshift provision and bring up the Nginx web front end.

```
[root@rh8-tools install-AI-operator]# oc get pod
NAME                                READY   STATUS    RESTARTS   AGE
assisted-service-6d6cb47d4d-rkt7q   1/1     Running   0          19h
ocp-metal-ui-7d99996ddc-jc76d       1/1     Running   0          19h
postgres-6dfdc886fc-4h6jj           1/1     Running   0          19h

[root@rh8-tools zero-touch-assisted-operator]# oc edit cm assisted-service-config

..omitted..
  OPENSHIFT_VERSIONS: ' {"4.6":{"display_name":"4.6.16","release_image":"quay.io/openshift-release-dev/ocp-release:4.6.16-x86_64","rhcos_image":"https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.6/4.6.8/rhcos-4.6.8-x86_64-live.x86_64.iso","rhcos_version":"46.82.202012051820-0","support_level":"production"},"4.7":{"display_name":"4.7.2","release_image":"quay.io/openshift-release-dev/ocp-release:4.7.2-x86_64","rhcos_image":"https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.7/4.7.0/rhcos-4.7.0-x86_64-live.x86_64.iso","rhcos_version":"47.83.202102090044-0","support_level":"production"},"4.8":{"display_name":"4.8","release_image":"quay.io/openshift-release-dev/ocp-release-nightly:4.8.0-0.nightly-2021-03-22-094046","rhcos_image":"https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.7/4.7.0/rhcos-4.7.0-x86_64-live.x86_64.iso","rhcos_version":"47.83.202102090044-0","support_level":"production"}}'

[root@rh8-tools zero-touch-assisted-operator]# oc delete $(oc get pod -o name | grep assisted)
```

Next, grab the node port for the service change the port in the configMap. Kill that pod and expose the service.

```
[root@rh8-tools install-AI-operator]# oc get svc assisted-service -o jsonpath='{.spec.ports[?(@.name=="assisted-service")].nodePort}'
30275

[root@rh8-tools install-AI-operator]# oc edit cm ocp-metal-ui
..omitted..
      location /api {
          proxy_pass http://assisted-service-assisted-installer.apps.mcm-cluster3.e2e.bos.redhat.com:30275;

[root@rh8-tools install-AI-operator]# oc delete $(oc get pod -o name | grep metal)
[root@rh8-tools install-AI-operator]# oc expose svc ocp-metal-ui
```

Now, we can see the CRDs added from the operator install. Note, the prior hive install requires ocm-2.3 to include the agentBareMetal install source.

```
[root@rh8-tools zero-touch-assisted-operator]# oc get crd | egrep -i 'clusterdeploy|agent|installenv'
agents.adi.io.my.domain                                                       2021-03-15T22:12:27Z
clusterdeployments.hive.openshift.io                              2021-03-25T15:49:16Z
installenvs.adi.io.my.domain                                                  2021-03-15T22:12:27Z

[root@rh8-tools install-AI-operator]# oc get crd clusterdeployments.hive.openshift.io -o yaml | grep " agentBareMetal:"
                  agentBareMetal:
```



## Creating the new Custom Resource manifests for OpenShift Deployment

The CR install process requires 4 objects for deployment.
1. The pull secret for the image

```
apiVersion: v1
kind: Secret
metadata:
  name: assisted-deployment-pull-secret
  namespace: assisted-installer
stringData:
  .dockerconfigjson:
# Red Hat pull secret for images
# ..redacted..
  type: kubernetes.io/dockerconfigjson

```
2. An SSH private key for manipulation of the deployed node via Hive.

```
apiVersion: v1
kind: Secret
metadata:
  name: assisted-deployment-ssh-private-key
  namespace: assisted-installer
stringData:
  ssh-privatekey: |-
# Private SSH key for hive use in deployment see ClusterDeployment manifest for public  
# ..redacted..
type: Opaque
```
3. The ClusterDeployment manifest which specifies the OCP version to be deployed and other information that would typically be defined in the install-config.

```
apiVersion: hive.openshift.io/v1
kind: ClusterDeployment
metadata:
  name: sno-assisted
  namespace: assisted-installer
spec:
  baseDomain: example.com
  clusterName: ocp-sno
  platform:
    agentBareMetal:
      # agentSelector matches InstallEnv 
      agentSelector:
        matchLabels:
          bla: aaa
      apiVIP: ""
      ingressVIP: ""
  provisioning:
    imageSetRef:
      name: "4.8"
    installConfigSecretRef:
      name: ocp-sno-install-config
    sshPrivateKeySecretRef:
      name: assisted-deployment-ssh-private-key
    installStrategy:
      agent:
        sshPublicKey:
        # Corresponding public key for private key 
        # ..redacted.. 
        networking:
          clusterNetwork:
            - cidr: 10.128.0.0/14
              hostPrefix: 23
          serviceNetwork:
            - 172.30.0.0/16
          machineNetwork:
            # Actual machine CIDR for hosts of cluster
            - cidr: 10.19.32.128/25
        provisionRequirements:
          # Single node Openshift 1 controlPlaneAgents 0 workerAgents
          controlPlaneAgents: 1
          workerAgents: 0
  pullSecretRef:
    name: assisted-deployment-pull-secret
```
4. The InstallEnv this kicks off the creation of the discovery ISO and is what you will boot the node to. 

```
apiVersion: adi.io.my.domain/v1alpha1
kind: InstallEnv
metadata:
  name: sno-assisted-ie
  namespace: assisted-installer
spec:
  clusterRef:
    name: sno-assisted
    namespace: assisted-installer
  agentLabelSelector:
    # agentSelector matches from ClusterDeployment
    matchLabels:
      bla: aaa
  pullSecretRef:
    name: assisted-deployment-pull-secret
```

Now, install the CRs and move the image to the local http server on this deployment host. The deployment ISO can be viewed via the InstallEnv CR. 

```
for cr in 00-pull-secret.yaml 01-private-key.yaml 02-clusterDeployment_ipv4-SNO.yaml 03-installenv.yaml;do oc create -f $cr;done
sleep 30
curl -o /var/www/html/embedded.iso `oc get installenv.adi.io.my.domain/sno-assisted-ie -o jsonpath='{.status.isoDownloadURL}'`
ls -al /var/www/html/embedded.iso
```

Now, use a quick redfish ansible playbook to mount the image and boot it. The ansible playbook is included in the repository at the end.

```
[root@rh8-tools install-CR-deploy]# cd ../ansible-host
[root@rh8-tools ansible-host]# ansible-galaxy collection install -r requirements.yml
[root@rh8-tools ansible-host]# ansible-playbook -i hosts playbook.yml -e discovery_image="http://$(hostname -i)/embedded.iso"
```

Once the host has boot and is showing ready in the Assisted Metal UI, if the install has NOT started you can manually kick it off via the API.

```
export URL=$(oc get route ocp-metal-ui -o jsonpath='{.spec.host}')
export CLUSTER_ID=$(oc get installenv.adi.io.my.domain/sno-assisted-ie -o jsonpath='{.status.isoDownloadURL}' | cut -d'/' -f 8)

curl -X POST "http://${URL}/api/assisted-install/v1/clusters/${CLUSTER_ID}/actions/install" -H "accept: application/json"
```

![Screen Shot 2021-03-26 at 9 49 05 AM](https://user-images.githubusercontent.com/7294149/112651532-7c432080-8e1a-11eb-8bbc-26060a90c696.png)

Enjoy your baremetal SNO cluster with minimal administrative overhead.  
