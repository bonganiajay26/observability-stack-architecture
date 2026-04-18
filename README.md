# Observability Stack Architecture
> Prometheus + Grafana + Loki + Tempo + OpenTelemetry — See everything, miss nothing

![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white)
![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-000000?style=for-the-badge&logo=opentelemetry&logoColor=white)

---

## Architecture Overview

```
Application Pod emits:
  /metrics (Prometheus) + Traces (OTLP) + Logs (stdout)
        ↓
Prometheus scrapes metrics (15s interval)
OTel Collector receives traces → Grafana Tempo
Promtail tails pod logs → Grafana Loki
        ↓
Grafana: unified dashboard (metrics + logs + traces)
        ↓
AlertManager → PagerDuty (P1) / Slack (P2)
        ↓
Engineer: alert → metrics → logs → traces
        ↓
Root cause in minutes, not hours
```

**Three Pillars:**
| Pillar | Tool | Answers |
|--------|------|---------|
| Metrics | Prometheus + Grafana | Is it slow? Since when? |
| Logs | Loki + Promtail | What exactly happened? |
| Traces | Tempo + OpenTelemetry | Which service caused the latency? |

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| kubectl | v1.28+ | [Install](https://kubernetes.io/docs/tasks/tools/) |
| Helm | v3.12+ | [Install](https://helm.sh/docs/intro/install/) |
| Kubernetes cluster | v1.28+ | Minikube / EKS / GKE / AKS |

---

## Execution Steps

### Step 1 — Start Cluster

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
kubectl get nodes
```

### Step 2 — Add Helm Repositories

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### Step 3 — Install Prometheus + Grafana + AlertManager

```bash
kubectl create namespace monitoring

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus/prometheus-values.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=monitoring \
  -n monitoring --timeout=300s

kubectl get pods -n monitoring
```

### Step 4 — Access Grafana Dashboard

```bash
# Port-forward Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring

# Get admin password
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo

# Open: http://localhost:3000
# Username: admin  |  Password: <from above>
```

### Step 5 — Install Loki + Promtail (Log Aggregation)

```bash
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --values loki/loki-values.yaml

kubectl get pods -n monitoring | grep loki

# Verify Promtail is running on all nodes (DaemonSet)
kubectl get daemonset -n monitoring | grep promtail
```

### Step 6 — Install Grafana Tempo (Distributed Tracing)

```bash
helm install tempo grafana/tempo \
  --namespace monitoring \
  --set tempo.storage.trace.backend=local \
  --set tempo.storage.trace.local.path=/var/tempo/traces

kubectl get pods -n monitoring | grep tempo
```

### Step 7 — Install OpenTelemetry Collector

```bash
kubectl apply -f otel/otel-collector.yaml

# Verify OTel Collector is running
kubectl get pods -n monitoring | grep otel
kubectl get svc -n monitoring | grep otel
```

### Step 8 — Add Loki + Tempo as Grafana Data Sources

```bash
# Port-forward Grafana (if not already)
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring

# Open Grafana → Configuration → Data Sources → Add data source
# Add Loki:  URL = http://loki:3100
# Add Tempo: URL = http://tempo:3100
# Save & Test each source
```

### Step 9 — Apply Prometheus Alert Rules

```bash
# Apply RED metric alerts + SLO burn-rate rules
kubectl apply -f prometheus/alert-rules.yaml
kubectl apply -f prometheus/slo-rules.yaml

# Verify rules are loaded
kubectl get prometheusrule -n monitoring
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
# Open: http://localhost:9090/rules
```

### Step 10 — Apply Grafana ServiceMonitor

```bash
kubectl apply -f grafana/grafana-configmap.yaml

# Verify ServiceMonitor is picked up by Prometheus
kubectl get servicemonitor -n monitoring
```

### Step 11 — Import RED Dashboard

```bash
# In Grafana UI:
# Dashboards → Import → Upload JSON file
# Select: grafana/dashboards/red-dashboard.json
# Select data source: Prometheus
# Import

# Dashboard shows:
# - Request rate (req/s)
# - Error rate (%)
# - p50 / p95 / p99 latency
# - Pod replica count
# - SLO error budget remaining
```

---

## Access All UIs

```bash
# Grafana (metrics + logs + traces)
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# http://localhost:3000

# Prometheus
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
# http://localhost:9090

# AlertManager
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 -n monitoring
# http://localhost:9093
```

---

## Testing the Stack

### Test Metrics Collection

```bash
# Check Prometheus is scraping your app
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
# Go to: http://localhost:9090/targets
# Verify your app pod appears as UP

# Query a metric
curl http://localhost:9090/api/v1/query?query=up
```

### Test Log Aggregation

```bash
# Generate some logs
kubectl logs -n production -l app=python-devops-app --tail=20

# In Grafana → Explore → Select Loki data source
# Query: {namespace="production", app="python-devops-app"}
# Logs should appear within 15 seconds
```

### Test Alerting

```bash
# Simulate high error rate (triggers HighErrorRate alert)
# In Grafana → Alerting → Alert rules
# Check AlertManager for active alerts
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 -n monitoring
# http://localhost:9093
```

### Test SLO Burn Rate

```bash
# View SLO dashboard in Grafana
# Watch error budget gauge — should show remaining budget %
kubectl get prometheusrule slo-burn-rate-alerts -n monitoring -o yaml
```

---

## Useful PromQL Queries

```promql
# Request rate (req/s)
sum(rate(http_requests_total{namespace="production"}[5m]))

# Error rate
sum(rate(http_requests_total{namespace="production",status=~"5.."}[5m]))
/ sum(rate(http_requests_total{namespace="production"}[5m]))

# p99 latency
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{namespace="production"}[5m]))
  by (le))

# Pod restarts
rate(kube_pod_container_status_restarts_total{namespace="production"}[15m])

# Node CPU usage
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

---

## Cleanup

```bash
helm uninstall monitoring -n monitoring
helm uninstall loki -n monitoring
helm uninstall tempo -n monitoring
kubectl delete -f otel/otel-collector.yaml
kubectl delete -f prometheus/alert-rules.yaml
kubectl delete -f prometheus/slo-rules.yaml
kubectl delete namespace monitoring
```

---

## Files

| File | Description |
|------|-------------|
| `prometheus/prometheus-values.yaml` | Full kube-prometheus-stack Helm values |
| `prometheus/alert-rules.yaml` | RED alerts + pod health + node + HPA alerts |
| `prometheus/slo-rules.yaml` | Multi-window SLO burn-rate alert rules |
| `loki/loki-values.yaml` | Loki + Promtail config with JSON log parsing |
| `grafana/dashboards/red-dashboard.json` | Grafana dashboard: Rate/Error/Latency/SLO |
| `grafana/grafana-configmap.yaml` | ConfigMap + ServiceMonitor for app scraping |
| `otel/otel-collector.yaml` | OTel Collector: receives OTLP → exports to Tempo |
| `install-observability.sh` | One-shot install script with port-forward info |
| `ARCHITECTURE.md` | Full diagram + LinkedIn post + storyboard |
