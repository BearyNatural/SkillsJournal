Step 1: Ensure your cluster is in a state that will support an upgrade; this includes checking the Kubernetes APIs used by resources deployed into the cluster, ensuring the cluster is free of any heal issues, etc. Customers should use EKS upgrade insights when evaluating their cluster's upgrade readiness
This is the most important step.
Step 2: Upgrade the control plane to the next minor version (i.e. 1.31 → 1.32)
Step 3: Upgrade the nodes in the data plane to match that of the control plane
Step 4: Upgrade the “core” addons (the addons provided by EKS - CoreDNS, VPC CNI, kube-proxy, etc.)
Step 5: Upgrade any additional applications that run on the cluster (i.e. - cluster-autoscaler)
Step 6: Upgrade any clients that communicate with the cluster (i.e. - kubectl)

https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html