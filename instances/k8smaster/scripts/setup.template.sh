#!/bin/bash -x

EXTERNAL_IP=$(curl -s -m 10 http://whatismyip.akamai.com/)
NAMESPACE=$(echo -n "${domain_name}" | sed "s/\.oraclevcn\.com//g")
FQDN_HOSTNAME=$(hostname -f)

# Pull instance metadata
curl -sL --retry 3 http://169.254.169.254/opc/v1/instance/ | tee /tmp/instance_meta.json

ETCD_ENDPOINTS=${etcd_endpoints}
export HOSTNAME=$(hostname)

export IP_LOCAL=$(ip route show to 0.0.0.0/0 | awk '{ print $5 }' | xargs ip addr show | grep -Po 'inet \K[\d.]+')

SUBNET=$(getent hosts $IP_LOCAL | awk '{print $2}' | cut -d. -f2)

## k8s_ver swap option
######################################
k8sversion="${k8s_ver}"

if [[ $k8sversion =~ ^[0-1]+\.[0-7]+ ]]; then
    SWAP_OPTION=""
else
    SWAP_OPTION="--fail-swap-on=false"
fi

## etcd
######################################

## Disable TX checksum offloading so we don't break VXLAN
######################################
BROADCOM_DRIVER=$(lsmod | grep bnxt_en | awk '{print $1}')
if [[ -n "$${BROADCOM_DRIVER}" ]]; then
   echo "Disabling hardware TX checksum offloading"
   ethtool --offload $(ip -o -4 route show to default | awk '{print $5}') tx off
fi


## Docker
######################################
until yum -y install docker-engine-${docker_ver}; do sleep 1 && echo -n "."; done

cat <<EOF > /etc/sysconfig/docker
OPTIONS="--selinux-enabled --log-opt max-size=${docker_max_log_size} --log-opt max-file=${docker_max_log_files}"
DOCKER_CERT_PATH=/etc/docker
GOTRACEBACK=crash
EOF

systemctl daemon-reload
systemctl enable docker
systemctl start docker

# Output /etc/environment_params
echo "IPV4_PRIVATE_0=$IP_LOCAL" >>/etc/environment_params
echo "ETCD_IP=$ETCD_ENDPOINTS" >>/etc/environment_params
echo "FQDN_HOSTNAME=$FQDN_HOSTNAME" >>/etc/environment_params

# Drop firewall rules
iptables -F

# Disable SELinux and firewall
sudo sed -i  s/SELINUX=enforcing/SELINUX=permissive/ /etc/selinux/config
setenforce 0
systemctl stop firewalld.service
systemctl disable firewalld.service

## Install Flex Volume Driver for OCI
#####################################
#mkdir -p /usr/libexec/kubernetes/kubelet-plugins/volume/exec/oracle~oci/
#curl -L --retry 3 https://github.com/oracle/oci-flexvolume-driver/releases/download/${flexvolume_driver_version}/oci -o/usr/libexec/kubernetes/kubelet-plugins/volume/exec/oracle~oci/oci
#chmod a+x /usr/libexec/kubernetes/kubelet-plugins/volume/exec/oracle~oci/oci
#mv /root/flexvolume-driver-secret.yaml /usr/libexec/kubernetes/kubelet-plugins/volume/exec/oracle~oci/config.yaml


# Install oci cloud controller manager
#kubectl apply -f /root/cloud-controller-secret.yaml
#kubectl apply -f https://github.com/oracle/oci-cloud-controller-manager/releases/download/${cloud_controller_version}/oci-cloud-controller-manager-rbac.yaml
#curl -sSL https://github.com/oracle/oci-cloud-controller-manager/releases/download/${cloud_controller_version}/oci-cloud-controller-manager.yaml | \
#    sed -e "s#10.244.0.0/16#${flannel_network_cidr}#g" | \
#    kubectl apply -f -

## install kube-dns
#kubectl create -f /root/services/kube-dns.yaml

## install kubernetes-dashboard
#kubectl create -f /root/services/kubernetes-dashboard.yaml

## Install Volume Provisioner of OCI
#kubectl create secret generic oci-volume-provisioner -n kube-system --from-file=config.yaml=/root/volume-provisioner-secret.yaml
#kubectl apply -f https://github.com/oracle/oci-volume-provisioner/releases/download/${volume_provisioner_version}/oci-volume-provisioner-rbac.yaml
#kubectl apply -f https://github.com/oracle/oci-volume-provisioner/releases/download/${volume_provisioner_version}/oci-volume-provisioner.yaml
#kubectl apply -f https://github.com/oracle/oci-volume-provisioner/releases/download/${volume_provisioner_version}/storage-class.yaml
#kubectl apply -f https://github.com/oracle/oci-volume-provisioner/releases/download/${volume_provisioner_version}/storage-class-ext3.yaml

## Mark OCI StorageClass as the default
#kubectl patch storageclass oci -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

#rm -f /root/volume-provisioner-secret.yaml

yum install -y nfs-utils

echo "Finished running setup.sh"
