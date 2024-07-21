#!/bin/bash -xe

CLUSTER_NAME=$1
CLUSTER_FQDN=$2
CLUSTER_USR=$3
CLUSTER_PWD=$4

sudo snap install kubectl --classic
sudo apt update
sudo apt install git
sudo snap install yq

# Install Azure CLI if not already installed
if ! command -v az &> /dev/null
then
    echo "Azure CLI not found. Installing..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    sudo apt-get install --only-upgrade -y azure-cli
else
    echo "Azure CLI found. Updating to the latest version..."
    sudo apt-get install --only-upgrade -y azure-cli
fi

git clone https://github.com/jonmosco/kube-ps1.git

echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
echo 'source "/home/adminuser/kube-ps1/kube-ps1.sh"' >> ~/.bashrc
echo "PS1='[\u@\h \W \$(kube_ps1)]\\$ '" >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
source <(kubectl completion bash)
source ~/.bashrc

mkdir /home/adminuser/.kube
mv /home/adminuser/client-key /home/adminuser/.kube/client-key
mv /home/adminuser/client-certificate /home/adminuser/.kube/client-certificate
mv /home/adminuser/certificate-authority /home/adminuser/.kube/certificate-authority

kubectl config set-cluster $CLUSTER_NAME \
    --certificate-authority /home/adminuser/.kube/certificate-authority \
    --server https://$CLUSTER_FQDN:443

kubectl config set-credentials $CLUSTER_USR \
    --user $CLUSTER_USR \
    --client-certificate /home/adminuser/.kube/client-certificate \
    --client-key /home/adminuser/.kube/client-key \
    --token $CLUSTER_PWD

kubectl config set-context $CLUSTER_NAME \
    --cluster $CLUSTER_NAME \
    --user $CLUSTER_USR \
    --token $CLUSTER_PWD \
    --namespace default

kubectl config use-context $CLUSTER_NAME
