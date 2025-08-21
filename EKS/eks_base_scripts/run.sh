#!/usr/bin/env bash
# Creates an EKS cluster, installs AWS Load Balancer Controller, and deploys a sample Ingress.
# Usage:
#   ./run.sh            # create and deploy
#   ./run.sh cleanup    # delete the cluster
set -euo pipefail

########################
# Config (edit as needed)
########################
export REGION="${REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-awslbc}"
export NODEGROUP_NAME="${NODEGROUP_NAME:-mng}"
export EKS_VERSION="${EKS_VERSION:-1.29}"
# If you want SSH access to nodes, set an existing EC2 key pair name here (or leave empty to disable)
export EC2_KEYPAIR_NAME="${EC2_KEYPAIR_NAME:-}"
# Optional: map an IAM principal as cluster-admin (leave blank to skip)
export ADMIN_IAM_ARN="${ADMIN_IAM_ARN:-}"

# AWS LB Controller version (policy & chart)
export LBC_VERSION="${LBC_VERSION:-v2.6.2}"

########################
# Derived variables
########################
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export AWS_DEFAULT_REGION="$REGION"

echo "=== Parameters ===
CLUSTER_NAME          = $CLUSTER_NAME
REGION                = $REGION
EKS_VERSION           = $EKS_VERSION
AWS_ACCOUNT_ID        = $AWS_ACCOUNT_ID
EC2_KEYPAIR_NAME      = ${EC2_KEYPAIR_NAME:-<none>}
ADMIN_IAM_ARN         = ${ADMIN_IAM_ARN:-<none>}
LBC_VERSION           = $LBC_VERSION
====================="

########################
# Helpers
########################
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
json() { jq -r "$1"; }

########################
# Pre-flight checks
########################
need aws
need eksctl
need kubectl
need helm
need jq
need curl

########################
# Cleanup path
########################
if [[ "${1:-}" == "cleanup" ]]; then
  echo "Cleanup requested..."
  set +e
  eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION"
  exit 0
fi

########################
# 1) Create EKS cluster
########################
echo "Creating EKS cluster '$CLUSTER_NAME' in $REGION..."

SSH_BLOCK=""
if [[ -n "$EC2_KEYPAIR_NAME" ]]; then
read -r -d '' SSH_BLOCK <<EOF || true
    ssh:
      allow: true
      publicKeyName: ${EC2_KEYPAIR_NAME}
EOF
fi

ADMIN_MAP=""
if [[ -n "$ADMIN_IAM_ARN" ]]; then
read -r -d '' ADMIN_MAP <<EOF || true
iamIdentityMappings:
  - arn: ${ADMIN_IAM_ARN}
    groups:
      - system:masters
    username: admin
    noDuplicateARNs: true
EOF
fi

eksctl create cluster -f - <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${REGION}
  version: "${EKS_VERSION}"

kubernetesNetworkConfig:
  ipFamily: IPv4

managedNodeGroups:
  - name: ${NODEGROUP_NAME}
    privateNetworking: true
    desiredCapacity: 2
    minSize: 1
    maxSize: 3
    instanceType: t3.medium
    volumeSize: 20
    labels:
      worker: linux
${SSH_BLOCK:+$SSH_BLOCK}

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy

iam:
  withOIDC: true

${ADMIN_MAP}

cloudWatch:
  clusterLogging:
    enableTypes: ["*"]
EOF

echo "Cluster created."

########################
# 2) kubeconfig
########################
echo "Updating kubeconfig..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo "Cluster nodes:"
kubectl get nodes -o wide
echo "System pods:"
kubectl -n kube-system get pods

########################
# 3) AWS Load Balancer Controller - IRSA + Policy + Helm
########################
echo "Ensuring AWS Load Balancer Controller IAM policy exists..."

POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
if ! aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" >/dev/null 2>&1; then
  echo "Downloading controller IAM policy ($LBC_VERSION) and creating it..."
  TMP_POLICY="$(mktemp)"
  curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json" -o "$TMP_POLICY"
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://$TMP_POLICY" >/dev/null
  rm -f "$TMP_POLICY"
  echo "Policy created: arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
else
  echo "Policy already exists: arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
fi

echo "Creating IRSA ServiceAccount for the controller..."
eksctl create iamserviceaccount \
  --region="$REGION" \
  --cluster="$CLUSTER_NAME" \
  --namespace="kube-system" \
  --name="aws-load-balancer-controller" \
  --attach-policy-arn="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" \
  --override-existing-serviceaccounts \
  --approve

echo "Adding Helm repo + installing controller..."
helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo update >/dev/null

VPC_ID="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)"

helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="$REGION" \
  --wait

echo "AWS Load Balancer Controller installed."
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller

########################
# 4) Sample echo app + Ingress
########################
echo "Deploying sample echo server + Service + Ingress..."

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: echoserver
EOF

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echoserver
  namespace: echoserver
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echoserver
  template:
    metadata:
      labels:
        app: echoserver
    spec:
      containers:
        - name: echoserver
          image: registry.k8s.io/e2e-test-images/echoserver:2.5
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
EOF

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: echoserver
  namespace: echoserver
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  selector:
    app: echoserver
EOF

kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echoserver
  namespace: echoserver
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/tags: Environment=dev,Team=test
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Exact
            backend:
              service:
                name: echoserver
                port:
                  number: 80
EOF

echo "Waiting for Ingress to get an address..."
for i in {1..60}; do
  HOST=$(kubectl -n echoserver get ingress echoserver -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "${HOST:-}" ]]; then
    break
  fi
  sleep 5
done

kubectl -n echoserver get deploy,svc,ingress -o wide
kubectl -n kube-system logs -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100 || true
kubectl -n echoserver describe ingress echoserver || true

if [[ -n "${HOST:-}" ]]; then
  echo "ALB hostname: http://${HOST}"
  echo "Try:   curl -I http://${HOST}/"
else
  echo "Ingress hostname not ready yet. Check controller logs and events."
fi

echo "Done."
