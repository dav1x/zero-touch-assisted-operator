for cr in 00-pull-secret.yaml 01-private-key.yaml 02-clusterDeployment_ipv4-SNO.yaml 03-installenv.yaml;do oc create -f $cr;done
sleep 30
curl -o /var/www/html/embedded.iso `oc get installenv.adi.io.my.domain/sno-assisted-ie -o jsonpath='{.status.isoDownloadURL}'`
ls -al /var/www/html/embedded.iso
