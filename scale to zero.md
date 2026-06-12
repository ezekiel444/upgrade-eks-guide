for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do \
  kubectl scale deployment --all --replicas=0 -n $ns; \
  kubectl scale statefulset --all --replicas=0 -n $ns; \
done

# Save replica counts first
kubectl get deployments,statefulsets -A -o json \
  | jq -r '.items[] | select(.spec.replicas > 0) | 
    "\(.metadata.namespace) \(.kind) \(.metadata.name) \(.spec.replicas)"' \
  > ~/replicas-backup-$(date +%Y%m%d).txt

cat ~/replicas-backup-$(date +%Y%m%d).txt  # verify before proceeding


# Scale down everything except system namespaces

PROTECTED_NS="kube-system kube-public kube-node-lease"

for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  if echo "$PROTECTED_NS" | grep -qw "$ns"; then
    echo "⏭  Skipping: $ns"
    continue
  fi
  echo "⬇  Scaling down: $ns"
  kubectl scale deployment --all --replicas=0 -n $ns 2>/dev/null
  kubectl scale statefulset --all --replicas=0 -n $ns 2>/dev/null
done

# Restore when you need it

while IFS=' ' read -r ns kind name replicas; do
  resource=$(echo "$kind" | tr '[:upper:]' '[:lower:]')
  echo "⬆  Restoring $resource/$name in $ns to $replicas replicas"
  kubectl scale $resource $name --replicas=$replicas -n $ns
done < ~/replicas-backup-$(date +%Y%m%d).txt