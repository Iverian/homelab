{ config, pkgs, ... }:
let
  namespace = "monitoring";
  grafanaHostname = "grafana.iverian.ru";
  grafanaOAuthSecret = "grafana-oauth";

  vmagentConfig = builtins.toJSON {
    global = {
      scrape_interval = "60s";
      scrape_timeout = "10s";
      external_labels.cluster = "homelab";
    };
    scrape_configs = [
      {
        job_name = "victoria-metrics";
        static_configs = [ { targets = [ "victoria-metrics:8428" ]; } ];
      }
      {
        job_name = "vmagent";
        static_configs = [ { targets = [ "localhost:8429" ]; } ];
      }
      {
        job_name = "kube-state-metrics";
        static_configs = [ { targets = [ "kube-state-metrics:8080" ]; } ];
      }
      {
        job_name = "node-exporter";
        static_configs = [ { targets = [ "node-exporter:9100" ]; } ];
      }
      {
        job_name = "kubernetes-apiservers";
        kubernetes_sd_configs = [ { role = "endpoints"; } ];
        scheme = "https";
        authorization.credentials_file = "/var/run/secrets/kubernetes.io/serviceaccount/token";
        tls_config.ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
        relabel_configs = [
          {
            source_labels = [
              "__meta_kubernetes_namespace"
              "__meta_kubernetes_service_name"
              "__meta_kubernetes_endpoint_port_name"
            ];
            action = "keep";
            regex = "default;kubernetes;https";
          }
        ];
      }
      {
        job_name = "kubernetes-nodes";
        kubernetes_sd_configs = [ { role = "node"; } ];
        scheme = "https";
        authorization.credentials_file = "/var/run/secrets/kubernetes.io/serviceaccount/token";
        tls_config.ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
        relabel_configs = [
          {
            action = "labelmap";
            regex = "__meta_kubernetes_node_label_(.+)";
          }
          {
            target_label = "__address__";
            replacement = "kubernetes.default.svc.cluster.local:443";
          }
          {
            source_labels = [ "__meta_kubernetes_node_name" ];
            target_label = "__metrics_path__";
            replacement = "/api/v1/nodes/$1/proxy/metrics";
          }
        ];
      }
      {
        job_name = "kubernetes-cadvisor";
        kubernetes_sd_configs = [ { role = "node"; } ];
        scheme = "https";
        authorization.credentials_file = "/var/run/secrets/kubernetes.io/serviceaccount/token";
        tls_config.ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
        relabel_configs = [
          {
            action = "labelmap";
            regex = "__meta_kubernetes_node_label_(.+)";
          }
          {
            target_label = "__address__";
            replacement = "kubernetes.default.svc.cluster.local:443";
          }
          {
            source_labels = [ "__meta_kubernetes_node_name" ];
            target_label = "__metrics_path__";
            replacement = "/api/v1/nodes/$1/proxy/metrics/cadvisor";
          }
          {
            target_label = "service";
            replacement = "kubelet";
          }
        ];
        metric_relabel_configs = [
          {
            source_labels = [ "__name__" ];
            action = "drop";
            regex = "container_(tasks_state|memory_failures_total|network_tcp_usage_total|network_udp_usage_total)";
          }
        ];
      }
      {
        job_name = "kubernetes-service-endpoints";
        kubernetes_sd_configs = [ { role = "endpoints"; } ];
        relabel_configs = [
          {
            source_labels = [ "__meta_kubernetes_service_annotation_prometheus_io_scrape" ];
            action = "keep";
            regex = "true";
          }
          {
            source_labels = [ "__meta_kubernetes_endpoint_port_name" ];
            action = "keep";
            regex = "http|metrics|http-metrics|prometheus";
          }
          {
            source_labels = [ "__meta_kubernetes_service_annotation_prometheus_io_scheme" ];
            action = "replace";
            target_label = "__scheme__";
            regex = "(https?)";
          }
          {
            source_labels = [
              "__address__"
              "__meta_kubernetes_service_annotation_prometheus_io_port"
            ];
            action = "replace";
            target_label = "__address__";
            regex = "([^:]+)(?::[0-9]+)?;([0-9]+)";
            replacement = "$1:$2";
          }
          {
            source_labels = [ "__meta_kubernetes_service_annotation_prometheus_io_path" ];
            action = "replace";
            target_label = "__metrics_path__";
            regex = "(.+)";
          }
          {
            action = "labelmap";
            regex = "__meta_kubernetes_service_label_(.+)";
          }
          {
            source_labels = [ "__meta_kubernetes_service_label_app" ];
            target_label = "job";
            regex = "(.+)";
          }
          {
            source_labels = [ "__meta_kubernetes_namespace" ];
            target_label = "namespace";
          }
          {
            source_labels = [ "__meta_kubernetes_service_name" ];
            target_label = "service";
          }
        ];
      }
      {
        job_name = "kubernetes-pods";
        kubernetes_sd_configs = [ { role = "pod"; } ];
        relabel_configs = [
          {
            source_labels = [ "__meta_kubernetes_pod_annotation_prometheus_io_scrape" ];
            action = "keep";
            regex = "true";
          }
          {
            source_labels = [ "__meta_kubernetes_pod_container_port_name" ];
            action = "keep";
            regex = "metrics|http-metrics|prometheus";
          }
          {
            source_labels = [ "__meta_kubernetes_pod_annotation_prometheus_io_scheme" ];
            action = "replace";
            target_label = "__scheme__";
            regex = "(https?)";
          }
          {
            source_labels = [ "__meta_kubernetes_pod_annotation_prometheus_io_path" ];
            action = "replace";
            target_label = "__metrics_path__";
            regex = "(.+)";
          }
          {
            source_labels = [
              "__address__"
              "__meta_kubernetes_pod_annotation_prometheus_io_port"
            ];
            action = "replace";
            target_label = "__address__";
            regex = "([^:]+)(?::[0-9]+)?;([0-9]+)";
            replacement = "$1:$2";
          }
          {
            action = "labelmap";
            regex = "__meta_kubernetes_pod_label_(.+)";
          }
          {
            source_labels = [ "__meta_kubernetes_namespace" ];
            target_label = "namespace";
          }
          {
            source_labels = [ "__meta_kubernetes_pod_name" ];
            target_label = "pod";
          }
          {
            source_labels = [ "__meta_kubernetes_pod_phase" ];
            action = "drop";
            regex = "Pending|Succeeded|Failed|Completed";
          }
        ];
      }
    ];
  };

  grafanaDatasource = builtins.toJSON {
    apiVersion = 1;
    datasources = [
      {
        name = "VictoriaMetrics";
        uid = "victoriametrics";
        type = "prometheus";
        access = "proxy";
        url = "http://victoria-metrics:8428";
        isDefault = true;
        editable = false;
        jsonData = {
          httpMethod = "POST";
          timeInterval = "60s";
          prometheusType = "Prometheus";
          cacheLevel = "High";
        };
      }
    ];
  };

  grafanaDashboardProvider = builtins.toJSON {
    apiVersion = 1;
    providers = [
      {
        name = "Homelab";
        orgId = 1;
        folder = "Homelab";
        type = "file";
        disableDeletion = true;
        editable = false;
        options.path = "/etc/grafana/dashboards";
      }
    ];
  };

  dashboards = {
    node-exporter = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/1860/revisions/45/download";
      hash = "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
    };
    kubernetes-global = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/15757/revisions/3/download";
      hash = "sha256-uG3MTxHQQkRraUJFnKIJcjbTPwMKmDwMwESeWMw0eDA=";
    };
    victoria-metrics = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/10229/revisions/61/download";
      hash = "sha256-k/RFtLoTBeuLhPne9UpPBQrd9a9Pg51Z5kSz+smnwxo=";
    };
    vmagent = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/12683/revisions/43/download";
      hash = "sha256-Cy5Re/Gx7Us98gwyukmfbDjdOE7cVnz50fz61JIMo2c=";
    };
    envoy-gateway = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/24460/revisions/1/download";
      hash = "sha256-ZbQyiSmqwdWB6c0MfgEGCZeLgteg1vfWgqfy5y7FGS4=";
    };
    envoy = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/24459/revisions/3/download";
      hash = "sha256-oz2XQBsKUNCAIUkcfnhr0hTNBi4zfXPbkELZ2ZJ4ZEk=";
    };
    gitea = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/17802/revisions/3/download";
      hash = "sha256-qZTa0R7JpVsGALw9mlRK5Y5WcII+B5u5qqjJOlwe9CE=";
    };
  };

  dashboardBase64 =
    name: dashboard:
    builtins.readFile (
      pkgs.runCommand "grafana-dashboard-${name}-base64" { } ''
        sed -E 's/\$\{DS_[A-Z0-9_-]+\}/victoriametrics/g' ${dashboard} \
          | base64 --wrap=0 > "$out"
      ''
    );
in
{
  sops = {
    secrets = {
      grafanaClientId = { };
      grafanaClientSecret = { };
    };
    templates.grafana-oauth = {
      content = builtins.toJSON {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          name = grafanaOAuthSecret;
          namespace = namespace;
        };
        stringData = {
          GF_AUTH_GENERIC_OAUTH_CLIENT_ID = config.sops.placeholder.grafanaClientId;
          GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = config.sops.placeholder.grafanaClientSecret;
        };
      };
      path = "/var/lib/rancher/k3s/server/manifests/monitoring-01-grafana-oauth.json";
      restartUnits = [ "k3s.service" ];
    };
  };

  services.k3s.manifests = {
    monitoring-00-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };

    monitoring-grafana-postgresql.content = {
      apiVersion = "acid.zalan.do/v1";
      kind = "postgresql";
      metadata = {
        name = "grafana-db";
        namespace = namespace;
      };
      spec = {
        teamId = "main";
        volume.size = "1Gi";
        numberOfInstances = 1;
        preparedDatabases.grafana = { };
        postgresql.version = "17";
        enableLogicalBackup = true;
      };
    };

    monitoring-victoria-metrics-pvc.content = {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "victoria-metrics";
        namespace = namespace;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "10Gi";
        storageClassName = "local-path";
      };
    };

    monitoring-victoria-metrics-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "victoria-metrics";
        namespace = namespace;
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "victoria-metrics";
        template = {
          metadata.labels.app = "victoria-metrics";
          spec = {
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
            };
            containers = [
              {
                name = "victoria-metrics";
                image = "victoriametrics/victoria-metrics:v1.156.0";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "-storageDataPath=/storage"
                  "-retentionPeriod=14d"
                  "-httpListenAddr=:8428"
                  "-memory.allowedBytes=268435456"
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 8428;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = "http";
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = "http";
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 30;
                };
                volumeMounts = [
                  {
                    name = "storage";
                    mountPath = "/storage";
                  }
                ];
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
              }
            ];
            volumes = [
              {
                name = "storage";
                persistentVolumeClaim.claimName = "victoria-metrics";
              }
            ];
          };
        };
      };
    };

    monitoring-victoria-metrics-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "victoria-metrics";
        namespace = namespace;
      };
      spec = {
        selector.app = "victoria-metrics";
        ports = [
          {
            name = "http";
            port = 8428;
            targetPort = "http";
          }
        ];
      };
    };

    monitoring-vmagent-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "vmagent-config";
        namespace = namespace;
      };
      data."prometheus.yml" = vmagentConfig;
    };

    monitoring-vmagent-service-account.content = {
      apiVersion = "v1";
      kind = "ServiceAccount";
      metadata = {
        name = "vmagent";
        namespace = namespace;
      };
    };

    monitoring-vmagent-cluster-role.content = {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRole";
      metadata.name = "monitoring-vmagent";
      rules = [
        {
          apiGroups = [ "" ];
          resources = [
            "nodes"
            "nodes/proxy"
            "services"
            "endpoints"
            "pods"
          ];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [ "discovery.k8s.io" ];
          resources = [ "endpointslices" ];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
        {
          nonResourceURLs = [ "/metrics" ];
          verbs = [ "get" ];
        }
      ];
    };

    monitoring-vmagent-cluster-role-binding.content = {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRoleBinding";
      metadata.name = "monitoring-vmagent";
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "monitoring-vmagent";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "vmagent";
          namespace = namespace;
        }
      ];
    };

    monitoring-vmagent-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "vmagent";
        namespace = namespace;
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "vmagent";
        template = {
          metadata = {
            labels.app = "vmagent";
            annotations."configmap.reloader.stakater.com/reload" = "vmagent-config";
          };
          spec = {
            serviceAccountName = "vmagent";
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
            };
            containers = [
              {
                name = "vmagent";
                image = "victoriametrics/vmagent:v1.156.0";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "-promscrape.config=/config/prometheus.yml"
                  "-remoteWrite.url=http://victoria-metrics:8428/api/v1/write"
                  "-remoteWrite.tmpDataPath=/queue"
                  "-remoteWrite.maxDiskUsagePerURL=536871040"
                  "-memory.allowedBytes=134217728"
                  "-httpListenAddr=:8429"
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 8429;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "25m";
                    memory = "64Mi";
                  };
                  limits = {
                    cpu = "250m";
                    memory = "256Mi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = "http";
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = "http";
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 30;
                };
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/config";
                    readOnly = true;
                  }
                  {
                    name = "queue";
                    mountPath = "/queue";
                  }
                ];
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
              }
            ];
            volumes = [
              {
                name = "config";
                configMap.name = "vmagent-config";
              }
              {
                name = "queue";
                emptyDir.sizeLimit = "513Mi";
              }
            ];
          };
        };
      };
    };

    monitoring-kube-state-metrics-service-account.content = {
      apiVersion = "v1";
      kind = "ServiceAccount";
      metadata = {
        name = "kube-state-metrics";
        namespace = namespace;
      };
    };

    monitoring-kube-state-metrics-cluster-role.content = {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRole";
      metadata.name = "monitoring-kube-state-metrics";
      rules = [
        {
          apiGroups = [ "" ];
          resources = [
            "configmaps"
            "secrets"
            "nodes"
            "pods"
            "services"
            "resourcequotas"
            "replicationcontrollers"
            "limitranges"
            "persistentvolumeclaims"
            "persistentvolumes"
            "namespaces"
            "endpoints"
          ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [ "apps" ];
          resources = [
            "statefulsets"
            "daemonsets"
            "deployments"
            "replicasets"
          ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [ "batch" ];
          resources = [
            "cronjobs"
            "jobs"
          ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [ "autoscaling" ];
          resources = [ "horizontalpodautoscalers" ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [ "networking.k8s.io" ];
          resources = [
            "ingresses"
            "networkpolicies"
          ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [ "policy" ];
          resources = [ "poddisruptionbudgets" ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [ "storage.k8s.io" ];
          resources = [
            "storageclasses"
            "volumeattachments"
          ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [ "discovery.k8s.io" ];
          resources = [ "endpointslices" ];
          verbs = [
            "list"
            "watch"
          ];
        }
        {
          apiGroups = [ "certificates.k8s.io" ];
          resources = [ "certificatesigningrequests" ];
          verbs = [
            "list"
            "watch"
          ];
        }
      ];
    };

    monitoring-kube-state-metrics-cluster-role-binding.content = {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRoleBinding";
      metadata.name = "monitoring-kube-state-metrics";
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "monitoring-kube-state-metrics";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "kube-state-metrics";
          namespace = namespace;
        }
      ];
    };

    monitoring-kube-state-metrics-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "kube-state-metrics";
        namespace = namespace;
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "kube-state-metrics";
        template = {
          metadata.labels.app = "kube-state-metrics";
          spec = {
            serviceAccountName = "kube-state-metrics";
            containers = [
              {
                name = "kube-state-metrics";
                image = "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.20.0";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--resources=configmaps,cronjobs,daemonsets,deployments,endpoints,endpointslices,horizontalpodautoscalers,ingresses,jobs,namespaces,networkpolicies,nodes,persistentvolumeclaims,persistentvolumes,poddisruptionbudgets,pods,replicasets,resourcequotas,secrets,services,statefulsets,storageclasses,volumeattachments"
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 8080;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "32Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/metrics";
                    port = "http";
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/metrics";
                    port = "http";
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 30;
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  runAsNonRoot = true;
                  runAsUser = 65534;
                  runAsGroup = 65534;
                  capabilities.drop = [ "ALL" ];
                };
              }
            ];
          };
        };
      };
    };

    monitoring-kube-state-metrics-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "kube-state-metrics";
        namespace = namespace;
      };
      spec = {
        selector.app = "kube-state-metrics";
        ports = [
          {
            name = "http";
            port = 8080;
            targetPort = "http";
          }
        ];
      };
    };

    monitoring-node-exporter-daemonset.content = {
      apiVersion = "apps/v1";
      kind = "DaemonSet";
      metadata = {
        name = "node-exporter";
        namespace = namespace;
      };
      spec = {
        selector.matchLabels.app = "node-exporter";
        template = {
          metadata.labels.app = "node-exporter";
          spec = {
            hostNetwork = true;
            hostPID = true;
            containers = [
              {
                name = "node-exporter";
                image = "quay.io/prometheus/node-exporter:v1.12.1";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--path.procfs=/host/proc"
                  "--path.sysfs=/host/sys"
                  "--path.rootfs=/host/root"
                  "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)"
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 9100;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "24Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "64Mi";
                  };
                };
                volumeMounts = [
                  {
                    name = "proc";
                    mountPath = "/host/proc";
                    readOnly = true;
                  }
                  {
                    name = "sys";
                    mountPath = "/host/sys";
                    readOnly = true;
                  }
                  {
                    name = "root";
                    mountPath = "/host/root";
                    readOnly = true;
                    mountPropagation = "HostToContainer";
                  }
                  {
                    name = "udev";
                    mountPath = "/run/udev/data";
                    readOnly = true;
                  }
                ];
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  runAsNonRoot = true;
                  runAsUser = 65534;
                  runAsGroup = 65534;
                  capabilities.drop = [ "ALL" ];
                };
              }
            ];
            volumes = [
              {
                name = "proc";
                hostPath.path = "/proc";
              }
              {
                name = "sys";
                hostPath.path = "/sys";
              }
              {
                name = "root";
                hostPath.path = "/";
              }
              {
                name = "udev";
                hostPath.path = "/run/udev/data";
              }
            ];
          };
        };
      };
    };

    monitoring-node-exporter-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "node-exporter";
        namespace = namespace;
      };
      spec = {
        selector.app = "node-exporter";
        ports = [
          {
            name = "http";
            port = 9100;
            targetPort = "http";
          }
        ];
      };
    };

    monitoring-grafana-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "grafana-config";
        namespace = namespace;
      };
      data = {
        "victoriametrics.yaml" = grafanaDatasource;
        "dashboards.yaml" = grafanaDashboardProvider;
      };
    };

    monitoring-grafana-dashboard-node-exporter.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "grafana-dashboard-node-exporter";
        namespace = namespace;
      };
      binaryData."node-exporter-full.json" = dashboardBase64 "node-exporter" dashboards.node-exporter;
    };

    monitoring-grafana-dashboard-kubernetes.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "grafana-dashboard-kubernetes";
        namespace = namespace;
      };
      binaryData."kubernetes-global.json" =
        dashboardBase64 "kubernetes-global" dashboards.kubernetes-global;
    };

    monitoring-grafana-dashboard-victoria-metrics.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "grafana-dashboard-victoria-metrics";
        namespace = namespace;
      };
      binaryData."victoria-metrics.json" = dashboardBase64 "victoria-metrics" dashboards.victoria-metrics;
    };

    monitoring-grafana-dashboard-vmagent.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "grafana-dashboard-vmagent";
        namespace = namespace;
      };
      binaryData."vmagent.json" = dashboardBase64 "vmagent" dashboards.vmagent;
    };

    monitoring-grafana-dashboard-envoy-gateway.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "grafana-dashboard-envoy-gateway";
        namespace = namespace;
      };
      binaryData."envoy-gateway.json" = dashboardBase64 "envoy-gateway" dashboards.envoy-gateway;
    };

    monitoring-grafana-dashboard-envoy.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "grafana-dashboard-envoy";
        namespace = namespace;
      };
      binaryData."envoy.json" = dashboardBase64 "envoy" dashboards.envoy;
    };

    monitoring-grafana-dashboard-gitea.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "grafana-dashboard-gitea";
        namespace = namespace;
      };
      binaryData."gitea.json" = dashboardBase64 "gitea" dashboards.gitea;
    };

    monitoring-grafana-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "grafana";
        namespace = namespace;
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "grafana";
        template = {
          metadata = {
            labels.app = "grafana";
            annotations = {
              "configmap.reloader.stakater.com/reload" =
                "grafana-config,grafana-dashboard-node-exporter,grafana-dashboard-kubernetes,grafana-dashboard-victoria-metrics,grafana-dashboard-vmagent,grafana-dashboard-envoy-gateway,grafana-dashboard-envoy,grafana-dashboard-gitea";
              "secret.reloader.stakater.com/reload" = grafanaOAuthSecret;
            };
          };
          spec = {
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 472;
              runAsGroup = 472;
              fsGroup = 472;
            };
            containers = [
              {
                name = "grafana";
                image = "grafana/grafana:12.4.15";
                imagePullPolicy = "IfNotPresent";
                ports = [
                  {
                    name = "http";
                    containerPort = 3000;
                  }
                ];
                envFrom = [ { secretRef.name = grafanaOAuthSecret; } ];
                env = [
                  {
                    name = "GF_SERVER_ROOT_URL";
                    value = "https://${grafanaHostname}";
                  }
                  {
                    name = "GF_DATABASE_TYPE";
                    value = "postgres";
                  }
                  {
                    name = "GF_DATABASE_HOST";
                    value = "grafana-db:5432";
                  }
                  {
                    name = "GF_DATABASE_NAME";
                    value = "grafana";
                  }
                  {
                    name = "GF_DATABASE_SSL_MODE";
                    value = "require";
                  }
                  {
                    name = "GF_DATABASE_USER";
                    valueFrom.secretKeyRef = {
                      name = "postgres-grafana-db";
                      key = "username";
                    };
                  }
                  {
                    name = "GF_DATABASE_PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = "postgres-grafana-db";
                      key = "password";
                    };
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_ENABLED";
                    value = "true";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_NAME";
                    value = "Authelia";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN";
                    value = "true";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_EMPTY_SCOPES";
                    value = "false";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_AUTH_URL";
                    value = "https://auth.iverian.ru/api/oidc/authorization";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_TOKEN_URL";
                    value = "https://auth.iverian.ru/api/oidc/token";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_API_URL";
                    value = "https://auth.iverian.ru/api/oidc/userinfo";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH";
                    value = "preferred_username";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH";
                    value = "name";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH";
                    value = "groups";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_USE_PKCE";
                    value = "true";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_SCOPES";
                    value = "openid profile email groups";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN";
                    value = "true";
                  }
                  {
                    name = "GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH";
                    value = "'GrafanaAdmin'";
                  }
                  {
                    name = "GF_AUTH_DISABLE_LOGIN_FORM";
                    value = "true";
                  }
                  {
                    name = "GF_USERS_ALLOW_SIGN_UP";
                    value = "true";
                  }
                  {
                    name = "GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION";
                    value = "true";
                  }
                  {
                    name = "GF_DATE_FORMATS_DEFAULT_TIMEZONE";
                    value = "Europe/Moscow";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "384Mi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/api/health";
                    port = "http";
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/api/health";
                    port = "http";
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                };
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/etc/grafana/provisioning/datasources/victoriametrics.yaml";
                    subPath = "victoriametrics.yaml";
                    readOnly = true;
                  }
                  {
                    name = "config";
                    mountPath = "/etc/grafana/provisioning/dashboards/dashboards.yaml";
                    subPath = "dashboards.yaml";
                    readOnly = true;
                  }
                  {
                    name = "dashboard-node-exporter";
                    mountPath = "/etc/grafana/dashboards/node-exporter-full.json";
                    subPath = "node-exporter-full.json";
                    readOnly = true;
                  }
                  {
                    name = "dashboard-kubernetes";
                    mountPath = "/etc/grafana/dashboards/kubernetes-global.json";
                    subPath = "kubernetes-global.json";
                    readOnly = true;
                  }
                  {
                    name = "dashboard-victoria-metrics";
                    mountPath = "/etc/grafana/dashboards/victoria-metrics.json";
                    subPath = "victoria-metrics.json";
                    readOnly = true;
                  }
                  {
                    name = "dashboard-vmagent";
                    mountPath = "/etc/grafana/dashboards/vmagent.json";
                    subPath = "vmagent.json";
                    readOnly = true;
                  }
                  {
                    name = "dashboard-envoy-gateway";
                    mountPath = "/etc/grafana/dashboards/envoy-gateway.json";
                    subPath = "envoy-gateway.json";
                    readOnly = true;
                  }
                  {
                    name = "dashboard-envoy";
                    mountPath = "/etc/grafana/dashboards/envoy.json";
                    subPath = "envoy.json";
                    readOnly = true;
                  }
                  {
                    name = "dashboard-gitea";
                    mountPath = "/etc/grafana/dashboards/gitea.json";
                    subPath = "gitea.json";
                    readOnly = true;
                  }
                  {
                    name = "data";
                    mountPath = "/var/lib/grafana";
                  }
                ];
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = [ "ALL" ];
                };
              }
            ];
            volumes = [
              {
                name = "config";
                configMap.name = "grafana-config";
              }
              {
                name = "dashboard-node-exporter";
                configMap.name = "grafana-dashboard-node-exporter";
              }
              {
                name = "dashboard-kubernetes";
                configMap.name = "grafana-dashboard-kubernetes";
              }
              {
                name = "dashboard-victoria-metrics";
                configMap.name = "grafana-dashboard-victoria-metrics";
              }
              {
                name = "dashboard-vmagent";
                configMap.name = "grafana-dashboard-vmagent";
              }
              {
                name = "dashboard-envoy-gateway";
                configMap.name = "grafana-dashboard-envoy-gateway";
              }
              {
                name = "dashboard-envoy";
                configMap.name = "grafana-dashboard-envoy";
              }
              {
                name = "dashboard-gitea";
                configMap.name = "grafana-dashboard-gitea";
              }
              {
                name = "data";
                emptyDir = { };
              }
            ];
          };
        };
      };
    };

    monitoring-grafana-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "grafana";
        namespace = namespace;
      };
      spec = {
        selector.app = "grafana";
        ports = [
          {
            name = "http";
            port = 3000;
            targetPort = "http";
          }
        ];
      };
    };

    monitoring-grafana-route.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "grafana";
        namespace = namespace;
      };
      spec = {
        hostnames = [ grafanaHostname ];
        parentRefs = [
          {
            name = "main";
            namespace = "envoy-gateway-system";
            sectionName = "https";
          }
        ];
        rules = [
          {
            matches = [
              {
                path = {
                  type = "PathPrefix";
                  value = "/";
                };
              }
            ];
            backendRefs = [
              {
                name = "grafana";
                port = 3000;
              }
            ];
          }
        ];
      };
    };
  };
}
