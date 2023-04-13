#!/bin/bash

function k8s_ops() {

  ## Set Kubernetes Configuration and Create MariaDB secret ##

  cd $basedir/aks
  terraform output -raw kube_config >$basedir/aks/config
  export KUBECONFIG=$basedir/aks/config
  chmod 400 $basedir/aks/config

  kubectl get nodes -o wide
  kubectl create ns mediawiki
  kubectl config set-context --current --namespace=mediawiki
  kubectl create secret generic mariadb --from-literal=root_pass=secret --from-literal=wiki_user_pass=wiki_pass123
}

function terraform_ops() {

  ## Provision AKS cluster on Azure ##

  az ad sp create-for-rbac --name="thghtwrksuser" --role="Owner" --scopes="/subscriptions/${subscription_id}" >sp_thghtwrks.json

  export TF_VAR_aks_service_principal_app_id=$(jq -r .appId sp_thghtwrks.json)
  export TF_VAR_aks_service_principal_client_secret=$(jq -r .password sp_thghtwrks.json)
  export ARM_SUBSCRIPTION_ID=${subscription_id}
  export ARM_TENANT_ID=$(jq -r .tenant sp_thghtwrks.json)

  cd $basedir/aks
  rm -f config

  terraform init
  terraform plan -out aks.plan
  if [ -f $basedir/aks/aks.plan ]; then
    terraform apply aks.plan
  else
    terraform apply -auto-approve
  fi
}

function build_images() {

  ## Build and Push images to ACR ##

  services=('mediawiki' 'mariadb')

  for svc in ${services[@]}; do
    cd $basedir/$svc
    echo -e "INFO: Building $svc image"
    if [ $svc == "mediawiki" ]; then
      az acr build --registry $ACR_NAME --image mediawiki:1.39.3 .
    else
      az acr build --registry $ACR_NAME --image mariadb:10.11.2 .
    fi

    cd $basedir/$svc/k8s_yaml
    kubectl apply -f deployment.yaml -n mediawiki
    kubectl apply -f svc.yaml -n mediawiki
  done
}

function configure_ingress_controller() {

  ## Download required images for ingress controller ##

  NAMESPACE=ingress-basic

  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update

  helm install ingress-nginx ingress-nginx/ingress-nginx \
    --create-namespace \
    --namespace $NAMESPACE \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

  REGISTRY_NAME=thghtwrksreg134
  SOURCE_REGISTRY=registry.k8s.io
  CONTROLLER_IMAGE=ingress-nginx/controller
  CONTROLLER_TAG=v1.2.1
  PATCH_IMAGE=ingress-nginx/kube-webhook-certgen
  PATCH_TAG=v1.1.1
  DEFAULTBACKEND_IMAGE=defaultbackend-amd64
  DEFAULTBACKEND_TAG=1.5

  az acr import --name $REGISTRY_NAME --source $SOURCE_REGISTRY/$CONTROLLER_IMAGE:$CONTROLLER_TAG --image $CONTROLLER_IMAGE:$CONTROLLER_TAG
  az acr import --name $REGISTRY_NAME --source $SOURCE_REGISTRY/$PATCH_IMAGE:$PATCH_TAG --image $PATCH_IMAGE:$PATCH_TAG
  az acr import --name $REGISTRY_NAME --source $SOURCE_REGISTRY/$DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG --image $DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG
}

function helm_deploy() {

  ## Helm Charts Deployment ##

  cd $basedir/aks

  ## Retrieve Service Principal Credentials ##
  export app_id=$(jq -r .appId sp_thghtwrks.json)
  export client_secret=$(jq -r .password sp_thghtwrks.json)

  ## Push to ACR Registry ##
  cd $basedir/helmcharts
  helm registry login $ACR_NAME.azurecr.io --username $app_id --password $client_secret
  helm push mediawiki-0.1.0.tgz oci://$ACR_NAME.azurecr.io/helm
  helm push mariadb-0.1.0.tgz oci://$ACR_NAME.azurecr.io/helm

  ## Deploy Helm Charts ##
  helm install mariadb --namespace mediawiki oci://$ACR_NAME.azurecr.io/helm/mariadb
  helm install mediawiki --namespace mediawiki oci://$ACR_NAME.azurecr.io/helm/mediawiki

}
basedir=$(pwd)
subscription_id=$1

cd $basedir/aks
terraform_ops
k8s_ops

RG=$(terraform output -raw resource_group_name)
ACR_NAME=$(terraform output -raw container_registry_name)

echo "Resource Group : $RG"
echo "Container Registry Name : $ACR_NAME"

## Login to ACR registry ##
az acr login -n $ACR_NAME

build_images
configure_ingress_controller

## Deploy Helm Charts ##
helm_deploy

sleep 60

access_ip=$(kubectl get ing mediawiki -n mediawiki -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo -e "--------------------------------------------------------"
echo -e "Access MediaWiki at URL: http://${access_ip}/mediawiki/"
echo -e "--------------------------------------------------------"