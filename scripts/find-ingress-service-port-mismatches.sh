#!/usr/bin/env bash
NS=${1:-suite}
echo "Scanning ingresses in namespace: $NS"
kubectl -n "$NS" get ingress -o json | jq -r '
  .items[] |
  {ing: .metadata.name, rules: .spec.rules?} |
  (.rules // [])[]? |
  .host as $host |
  .http.paths[]? |
  {ingress: .ing?, host: $host, path: .path, svc: .backend.service.name, port: (.backend.service.port.number // .backend.service.port.name)}
' | jq -s .
# now validate each pair
kubectl -n "$NS" get ingress -o json | jq -r '.items[] | .metadata.name' | while read IN; do
  kubectl -n "$NS" get ingress "$IN" -o json | \
  jq -r --arg IN "$IN" '.spec.rules[]?.http.paths[]? | "\($IN) \(.backend.service.name) \(.backend.service.port.number // .backend.service.port.name)"'
done | while read IN SVC PORT; do
  # get service ports
  if ! kubectl -n "$NS" get svc "$SVC" -o json >/dev/null 2>&1; then
    echo "MISSING SERVICE: ingress=$IN references missing service $SVC"
    continue
  fi
  kubectl -n "$NS" get svc "$SVC" -o json | jq -r '.spec.ports[] | (.name // "") + " " + (.port|tostring) + " " + (.targetPort|tostring)' > /tmp/svc_ports.$$
  if ! grep -q -E "(^| )$PORT( |$)" /tmp/svc_ports.$$; then
    echo "MISMATCH: ingress=$IN -> service=$SVC port=$PORT  -> service ports: "
    cat /tmp/svc_ports.$$
  fi
done
rm -f /tmp/svc_ports.$$
