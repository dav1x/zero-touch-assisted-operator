for cr in 00-pull-secret.yaml 01-private-key.yaml 02-clusterDeployment_ipv4-SNO.yaml 03-installenv.yaml;do oc delete -f $cr;done
