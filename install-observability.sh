#!/bin/bash
# install-observability.sh — Install complete Prometheus + Grafana + Loki + Tempo stack

set -e

echo "=== Installing Production Observability Stack ==="

# ── Add Helm repos ──
echo "[1/5] Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# ── Install kube-prometheus-stack (Prometheus + Grafana + AlertManager) ──
echo "[2/5] Installing kube-prometheus-stack..."
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus/prometheus-values.yaml \
  --wait

# ── Install Loki + Promtail ──
echo "[3/5] Installing Loki + Promtail (log aggregation)..."
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --values loki/loki-values.yaml \
  --wait

# ── Install Grafana Tempo (distributed tracing) ──
echo "[4/5] Installing Grafana Tempo (tracing)..."
helm install tempo grafana/tempo \
  --namespace monitoring \
  --set tempo.storage.trace.backend=local \
  --set tempo.storage.trace.local.path=/var/tempo/traces \
  --wait

# ── Apply Prometheus alert rules ──
echo "[5/5] Applying Prometheus alert rules and SLO rules..."
kubectl apply -f prometheus/alert-rules.yaml
kubectl apply -f prometheus/slo-rules.yaml

echo ""
echo "=== Observability Stack Installed ==="
echo ""
echo "Accessing Grafana:"
echo "  kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "  URL: http://localhost:3000"
echo "  Username: admin"
echo "  Password: $(kubectl get secret monitoring-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)"
echo ""
echo "Accessing Prometheus:"
echo "  kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring"
echo "  URL: http://localhost:9090"
echo ""
echo "Accessing AlertManager:"
echo "  kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 -n monitoring"
echo "  URL: http://localhost:9093"
echo ""
echo "Stack status:"
kubectl get pods -n monitoring
