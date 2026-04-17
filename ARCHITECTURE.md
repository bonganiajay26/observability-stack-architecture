# Observability Stack Architecture
> Senior DevOps Architect | Production-Grade | LinkedIn Content Series

---

## 1. Architecture Title

**"See Everything, Miss Nothing: Production Observability Stack — Prometheus + Grafana + Loki + Tempo + OpenTelemetry on Kubernetes"**

---

## 2. Problem Statement

**The Real-World Engineering Problem:**

Your app is down. Your users are screaming. Your engineers are running:

```bash
kubectl get pods
kubectl logs pod-name-abc123 --tail=100
kubectl describe pod pod-name-abc123
```

And finding nothing. Because:
- The crashing pod already restarted — logs gone
- The issue is a slow 3rd party API — no traces to see where time is spent
- CPU looks fine in the dashboard — but the real problem is p99 latency, not p50
- 47 microservices and you don't know which one introduced the regression

**This is the observability gap. And it kills MTTR (Mean Time to Restore).**

Modern production systems require three pillars of observability working together:

| Pillar | Tool | Answers |
|---|---|---|
| **Metrics** | Prometheus + Grafana | "Is it slow? By how much? Since when?" |
| **Logs** | Loki + Grafana | "What happened exactly? What error?" |
| **Traces** | Tempo + Grafana | "Where did the latency come from? Which service?" |

Add alerting (AlertManager + PagerDuty) and you have a complete observability stack where any incident can be diagnosed from dashboard to root cause in minutes, not hours.

---

## 3. Tools and Technologies Used

| Category | Tool |
|---|---|
| **Metrics Collection** | Prometheus |
| **Metrics Visualization** | Grafana |
| **Log Aggregation** | Grafana Loki |
| **Distributed Tracing** | Grafana Tempo |
| **Instrumentation** | OpenTelemetry (OTel SDK + Collector) |
| **Alerting** | AlertManager |
| **On-Call** | PagerDuty / Opsgenie |
| **Uptime Monitoring** | Blackbox Exporter |
| **Node Metrics** | Node Exporter |
| **Kubernetes Metrics** | kube-state-metrics |
| **Log Shipping** | Promtail / FluentBit |
| **Cost Observability** | Kubecost |
| **Synthetic Monitoring** | Grafana k6 |
| **SLO Management** | Sloth / Pyrra |
| **Deployment** | Helm (kube-prometheus-stack) |

---

## 4. Architecture Diagram Flow

```
  ┌─────────────────────────────────────────────────────────────────┐
  │                    KUBERNETES CLUSTER                            │
  │                                                                  │
  │  ┌──────────────────────────────────────────────────────────┐   │
  │  │                  APPLICATION PODS                         │   │
  │  │                                                          │   │
  │  │   Flask / Node / Java   ←── OpenTelemetry SDK            │   │
  │  │                              (auto-instrumentation)       │   │
  │  │   Exposes: /metrics (Prometheus format)                  │   │
  │  │   Emits:   Traces → OTel Collector                       │   │
  │  │   Writes:  Logs → stdout (structured JSON)               │   │
  │  └──────────┬──────────────────┬────────────────┬───────────┘   │
  │             │ metrics scrape   │ traces push     │ log tail      │
  │             ↓                  ↓                 ↓               │
  │  ┌──────────────┐  ┌────────────────────┐  ┌──────────────┐    │
  │  │  Prometheus  │  │  OTel Collector     │  │  Promtail /  │    │
  │  │  (scrapes    │  │  (receives, batches,│  │  FluentBit   │    │
  │  │  15s interval│  │   exports traces)   │  │  (tail pod   │    │
  │  │  + stores    │  └──────────┬──────────┘  │   stdout)    │    │
  │  │  TSDB)       │             ↓              └──────┬───────┘    │
  │  └──────┬───────┘   ┌─────────────────┐            ↓            │
  │         │           │  Grafana Tempo   │   ┌────────────────┐   │
  │         ↓           │  (trace storage) │   │  Grafana Loki  │   │
  │  ┌──────────────┐   └─────────────────┘   │  (log storage) │   │
  │  │ AlertManager │                          └────────────────┘   │
  │  │ (evaluate    │                                                │
  │  │  alert rules)│   ┌─────────────────────────────────────┐    │
  │  └──────┬───────┘   │          Grafana                     │    │
  │         │           │  (unified UI for all 3 pillars)      │    │
  │         │           │                                      │    │
  │         └──────────→│  Data Sources:                       │    │
  │                     │  - Prometheus (metrics)              │    │
  │                     │  - Loki (logs)                       │    │
  │                     │  - Tempo (traces)                    │    │
  │                     │                                      │    │
  │                     │  Dashboards:                         │    │
  │                     │  - RED metrics (Rate/Errors/Duration)│    │
  │                     │  - Node / Cluster health             │    │
  │                     │  - Service dependency maps           │    │
  │                     │  - SLO burn rate                     │    │
  │                     └─────────────────────────────────────┘    │
  └─────────────────────────────────────────────────────────────────┘
                                    ↓ alerts
  ┌─────────────────────────────────────────────────────────────────┐
  │                     ALERTING CHAIN                               │
  │                                                                  │
  │   AlertManager → Routes by severity:                            │
  │   ├── P1 (Critical):  PagerDuty → On-call engineer woken        │
  │   ├── P2 (Warning):   Slack #alerts channel                     │
  │   └── P3 (Info):      Grafana annotation on dashboard           │
  └─────────────────────────────────────────────────────────────────┘
```

**Simplified Linear Flow:**

```
Application Pod emits: metrics (/metrics) + traces (OTLP) + logs (stdout)
        ↓
Prometheus scrapes metrics every 15s → stored in TSDB
OTel Collector receives traces → forwards to Grafana Tempo
Promtail tails pod logs → streams to Grafana Loki
        ↓
Grafana: unified dashboard pulling all three data sources
        ↓
AlertManager evaluates Prometheus rules → fires on breach
        ↓
PagerDuty (P1) / Slack (P2) → engineer investigates
        ↓
Engineer: Grafana dashboard → Logs → Traces (one pane of glass)
        ↓
Root cause identified in minutes, not hours
```

---

## 5. Component Explanation

### OpenTelemetry SDK + Collector
The universal instrumentation standard. Language SDKs (Python, Java, Go, Node) auto-instrument your app with zero code changes — HTTP requests, DB calls, outbound APIs all traced automatically. The OTel Collector is a vendor-neutral proxy: receive traces in any format (OTLP, Jaeger, Zipkin), process them (sample, filter, enrich), and export to Tempo (or Datadog, Jaeger, etc.) without changing application code.

### Prometheus
Pull-based metrics database. Scrapes `/metrics` endpoints from every pod, node, and Kubernetes component every 15 seconds. Stores time-series data in its local TSDB. PromQL (Prometheus Query Language) allows precise metric computation: rates, percentiles, histograms. Rule files define alerting conditions evaluated continuously.

### Grafana Loki
Log aggregation designed for Kubernetes. Unlike Elasticsearch (which indexes every field), Loki only indexes labels (pod name, namespace, level). This makes it 10× cheaper to run at scale. LogQL queries filter by label first, then grep the log content — fast and cost-efficient.

### Grafana Tempo
Distributed trace storage. Receives traces from OTel Collector, stores them indexed by trace ID. Grafana connects Tempo to Loki and Prometheus — click a span in a trace → see the logs from that exact pod at that exact timestamp. This is "exemplars" — the killer feature for fast RCA.

### AlertManager
Prometheus sends alerts to AlertManager when rule conditions are met. AlertManager deduplicates, groups, and routes: a 50-pod outage fires one page, not 50. Routes P1 to PagerDuty, P2 to Slack, silences maintenance windows. Inhibition rules suppress child alerts when a parent is already firing.

### kube-state-metrics + Node Exporter
kube-state-metrics exposes Kubernetes object state as Prometheus metrics: deployment replica count, pod phase, PVC bound status. Node Exporter exposes host-level metrics: disk I/O, network traffic, filesystem usage. Together they give complete cluster visibility without writing any custom code.

### SLO Management (Sloth / Pyrra)
Defines Service Level Objectives as code: "99.9% of requests must complete in under 500ms over a 30-day window." Sloth generates Prometheus recording rules and multi-burn-rate alert rules automatically. Grafana dashboards show remaining error budget — engineers know exactly how much reliability risk they have before the next deploy.

---

## 6. Animation Storyboard

```
Scene 1 — The Dark Room (0:00–0:08)
  Visual: On-call engineer at 3AM, dark room, phone buzzing
  Text: "Alert: 500 errors spiking in production"
  Effect: PagerDuty notification appears, p5 of the RED dashboard lights up red

Scene 2 — Grafana Opens — Metrics (0:08–0:18)
  Visual: RED dashboard — request rate drops, error rate spikes to 12%, latency p99 explodes
  Text: "Metrics: error rate 0.1% → 12% at 2:47AM — which service?"
  Effect: service dependency graph appears, one node highlighted red

Scene 3 — Pivot to Logs (0:18–0:28)
  Visual: Grafana → Explore → Loki query for that service
  Text: "Logs: 'connection refused: postgres:5432' — DB connection failing"
  Effect: error log lines appear highlighted in red, timestamps align with metric spike

Scene 4 — Pivot to Traces (0:28–0:40)
  Visual: Grafana → Tempo — trace waterfall for a failing request
  Text: "Trace: 98% of latency in DB query span — query timing out"
  Effect: slow span highlighted in orange, DB call shown taking 29 seconds

Scene 5 — Root Cause (0:40–0:48)
  Visual: kubectl → describe pod postgres → OOM killed at 2:46AM
  Text: "Root cause: Postgres pod OOM killed, restarting — connection pool exhausted"
  Effect: memory usage graph peaks then drops (restart), timeline aligns perfectly

Scene 6 — AlertManager Routing (0:48–0:55)
  Visual: AlertManager UI — alert grouped by cluster, routed to PagerDuty
  Text: "AlertManager: deduplicated 47 pod alerts → 1 page to on-call"
  Effect: 47 individual alerts collapse into single PagerDuty incident

Scene 7 — SLO Dashboard (0:55–1:05)
  Visual: SLO burn rate dashboard — error budget burning fast
  Text: "30-day SLO: 99.9% | Error budget remaining: 43% (after 14-minute incident)"
  Effect: error budget bar decreasing, burn rate gauge in red

Scene 8 — Resolution (1:05–1:15)
  Visual: Postgres memory limit increased → pod restarts → RED metrics return to green
  Text: "Resolution: VPA recommendation applied — memory limit 512Mi → 2Gi"
  Effect: all dashboards return to green, PagerDuty incident resolved

Scene 9 — One Pane of Glass (1:15–1:20)
  Visual: Grafana split-screen: metrics + logs + traces linked in one view
  Text: "Metrics → Logs → Traces: from alert to root cause in 8 minutes"
  Effect: three panels highlight simultaneously showing correlated data
```

---

## 7. Real Production Example

### Uber
Uber's observability platform (M3 + custom tooling, recently migrating toward Prometheus-compatible APIs) handles 600 million metrics per minute from 4,000+ microservices. Their trace sampling strategy: 100% sample errors and slow requests (p99+), 1% sample normal traffic — Tempo-style head-based sampling controlled at the OTel Collector.

### Cloudflare
Cloudflare runs Grafana + Prometheus at extreme scale across 270+ data centers. Their key insight: alert on symptoms (user-visible error rate, latency) not causes (CPU, memory). AlertManager multi-burn-rate alerts on SLO error budget consumption — a 2% burn in 1 hour pages immediately, a 0.1% burn over 24 hours pages during business hours.

### Monzo (UK Digital Bank)
Monzo's on-call engineers go from PagerDuty alert to root cause in under 10 minutes using their Grafana-linked observability stack. Their runbooks live as Grafana dashboard annotations. When an alert fires, the dashboard automatically shows: related logs, recent deployments (as annotations), and linked traces for the anomalous time window.

---

## 8. LinkedIn Post Content

---

📊 **Your app went down for 47 minutes. Your logs showed nothing. Your metrics were green. What went wrong?**

Metrics without logs is like having a heart rate monitor but no blood test.
Logs without traces is like reading chapters but missing the story arc.
Traces without metrics is like seeing the path but not knowing if it's fast or slow.

**You need all three. Here's the production observability stack.**

---

**The Three Pillars:**

📈 **Metrics — Prometheus + Grafana**
Answers: "Is it slow? How many errors? Since when?"
→ Scrapes /metrics from every pod every 15 seconds
→ PromQL computes rates, p99 latency, error ratios
→ AlertManager fires before users notice

📋 **Logs — Grafana Loki**
Answers: "What exactly happened? What was the error message?"
→ Promtail tails every pod's stdout
→ Indexed by label only (namespace, pod, level) → 10× cheaper than ELK
→ LogQL filters: namespace=prod, level=error → exact error context

🔗 **Traces — Grafana Tempo + OpenTelemetry**
Answers: "Which service caused the latency? Which DB query took 29 seconds?"
→ OTel SDK auto-instruments: no code changes needed
→ Distributed waterfall: see every hop across 12 microservices
→ Exemplars: click a slow metric → jump directly to the trace

---

**The killer feature nobody talks about:**

Grafana can correlate all three in one click:
→ See error spike in metrics
→ Click: "Show logs for this time window" → Loki query auto-generated
→ Click trace ID in a log line → Tempo opens the full trace

From alert to root cause: 8 minutes. Without this stack: 3 hours.

---

**Alerting (non-negotiable):**
→ P1: AlertManager → PagerDuty → engineer woken
→ Alert on symptoms: error rate, p99 latency — NOT CPU/memory
→ SLO burn rate alerts: fire before you've spent your error budget

What does your observability stack look like today? One pillar, two, or all three? 👇

---

## 9. Hashtags

```
#Observability
#Prometheus
#Grafana
#OpenTelemetry
#Kubernetes
#DevOps
#SRE
#Loki
#DistributedTracing
#PlatformEngineering
```

---

## kube-prometheus-stack Helm Install (Production)

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install full observability stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --set grafana.adminPassword=<from-vault> \
  --set alertmanager.config.global.slack_api_url=<from-vault>
```

## Loki Stack Helm Install

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=20Gi
```

## Prometheus Alert Rule (SLO Burn Rate)

```yaml
# slo-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-burn-rate-alerts
  namespace: monitoring
spec:
  groups:
    - name: slo.rules
      rules:
        - alert: HighErrorBudgetBurn
          expr: |
            (
              rate(http_requests_total{status=~"5.."}[1h])
              /
              rate(http_requests_total[1h])
            ) > 0.001 * 14.4   # 14.4× burn rate = 1hr window SLO breach
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "SLO error budget burning at 14.4× rate"
            description: "Service {{ $labels.service }} will exhaust error budget in < 1 hour"
            runbook_url: "https://runbooks.internal/slo-burn"
```
