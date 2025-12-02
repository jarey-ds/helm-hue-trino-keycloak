# Trino and Apache Hue Helm Chart

This Helm chart deploys Trino and Apache Hue with integrated Trino editor support, enabling SQL federation and data mesh capabilities.

## Prerequisites

- Kubernetes cluster
- Helm 3.x
- Access to the following Helm repositories:
  - Trino: `https://trinodb.github.io/charts/`
  - Apache Hue: `https://helm.gethue.com`

## Installation

### 1. Add Helm Repositories

```bash
helm repo add trino https://trinodb.github.io/charts/
helm repo add gethue https://helm.gethue.com
helm repo update
```

### 2. Install Dependencies

Before installing the chart, update Helm dependencies:

```bash
helm dependency update
```

This will download the Trino and Apache Hue charts into the `charts/` directory.

### 3. Deploy the Chart

Install the chart with default values:

```bash
helm install trino-hue . --namespace <your-namespace> --create-namespace
```

Or install with custom values:

```bash
helm install trino-hue . -f values.yaml --namespace <your-namespace> --create-namespace
```

## Configuration

### Trino Configuration

The Trino configuration is based on the `trino.yaml` reference file. Key settings include:

- **Image Tag**: Default is `478` (can be overridden in `values.yaml`)
- **Workers**: Default is `3` workers
- **JVM Heap Size**: Default is `8G` for both coordinator and workers

Example Trino configuration in `values.yaml`:

```yaml
trino:
  enabled: true
  image:
    tag: "478"
  server:
    workers: 3
  coordinator:
    jvm:
      maxHeapSize: "8G"
  worker:
    jvm:
      maxHeapSize: "8G"
```

### Apache Hue Configuration

Hue is automatically configured to connect to Trino through a post-install hook that patches the Hue ConfigMap. The configuration follows the [official Hue Trino integration guide](https://gethue.com/blog/2024-06-26-integrating-trino-editor-in-hue-supporting-data-mesh-and-sql-federation/).

**PostgreSQL Version**: The Hue chart defaults to PostgreSQL 9.5, but Hue requires PostgreSQL 12 or later. When `hue.database.create: true`, this chart automatically patches the PostgreSQL deployment to use PostgreSQL 15 (configurable via `hue.database.image`).

**Data Format Compatibility**: The Hue chart defaults to PostgreSQL 9.5, which creates data incompatible with PostgreSQL 12+. To prevent this issue, the chart automatically deletes any existing PVC after patching the deployment (controlled by `hue.database.deleteExistingPVC`, default: `true`). This ensures PostgreSQL 15 starts with a fresh, compatible data directory. **Warning**: Setting `deleteExistingPVC: true` will delete all existing data!

**Automatic Configuration**: A post-install Helm hook automatically adds the Trino interpreter configuration to Hue's `hue.ini` file after deployment. The hook:
1. Retrieves the Hue ConfigMap
2. Adds or updates the Trino interpreter configuration with the correct service URL
3. Restarts the Hue deployment to pick up the new configuration

Key settings:

- **Trino Service URL**: Automatically configured based on release name (default: `<release-name>-trino:8080`)
- **Authentication**: Supports LDAP username/password or unsecured connections

#### Using a Created PostgreSQL Database (Default)

Example configuration for creating a PostgreSQL database:

```yaml
hue:
  enabled: true
  
  # Database configuration - creating a new PostgreSQL instance
  database:
    create: true
    persist: true
    storageName: "standard"  # Storage class for PVC (default: "standard" for Minikube)
    deleteExistingPVC: false  # Set to true to delete existing PVC with incompatible data
    image: "postgres:15"  # PostgreSQL 12+ required (default: postgres:15)
    host: "postgres-hue"
    port: 5432
    user: "hue"
    password: "hue"
    name: "hue"
  
  trino:
    serviceName: ""  # Optional: override default service name (defaults to <release-name>-trino)
    port: 8080
    auth_username: ""  # Set for LDAP authentication
    auth_password: ""  # Set for LDAP authentication
  
  # Ingress configuration
  ingress:
    create: true
    domain: "hue.local"  # Default domain (update /etc/hosts or configure DNS)
    type: "nginx"  # Options: nginx, nginx-ssl, nginx-ssl-staging, traefik
```

#### Using an Existing PostgreSQL Database

If you have an existing PostgreSQL database (version 12+) in your cluster, you can configure Hue to use it:

```yaml
hue:
  enabled: true
  
  # Database configuration - using existing PostgreSQL
  database:
    create: false  # Set to false to use existing database
    engine: "postgresql_psycopg2"
    host: "your-postgres-service.your-namespace.svc.cluster.local"  # Service name or FQDN
    port: 5432
    user: "your-db-user"
    password: "your-db-password"
    # password_script: "echo ${DATABASE_PASSWORD}"  # Alternative: use password script
    name: "your-database-name"
  
  trino:
    serviceName: ""
    port: 8080
    auth_username: ""
    auth_password: ""
```

**Important**: When using an existing database, ensure:
- PostgreSQL version is 12 or later
- The database and user specified in the configuration exist
- The database is accessible from the Hue pods (check network policies and service connectivity)
- The database has been initialized (Hue will create its schema on first connection)

**How it works**: The chart uses the [Apache Hue Helm chart](https://github.com/cloudera/hue/tree/master/tools/kubernetes/helm/hue) which stores configuration in a ConfigMap. A post-install hook patches this ConfigMap to add the Trino interpreter configuration with the dynamically generated service name.

### Customizing Trino Service Name

If your Trino service has a different name, you can override it:

```yaml
hue:
  trino:
    serviceName: "custom-trino-service"
```

## Accessing the Services

### Trino

Access Trino coordinator:

```bash
kubectl port-forward svc/<release-name>-trino-coordinator 8080:8080 -n <namespace>
```

Then access Trino UI at `http://localhost:8080`

### Apache Hue

Access Hue web interface:

**Via Ingress** (if enabled):
- Default domain: `http://hue.local`
- Ensure your `/etc/hosts` includes: `127.0.0.1 hue.local` (or configure DNS)
- Or use the configured domain from `hue.ingress.domain`

**Via Port Forward**:
```bash
kubectl port-forward svc/<release-name>-hue 8888:8888 -n <namespace>
```

Then access Hue at `http://localhost:8888`

## Using Trino in Hue

Once both services are running:

1. Access the Hue web interface
2. Navigate to the Query Editor
3. Select "Trino" as the interpreter
4. Start querying your data sources through Trino

## Troubleshooting

### Hue Cannot Connect to Trino

1. Verify both services are running:
   ```bash
   kubectl get pods -n <namespace>
   ```

2. Check the Trino service name matches the configuration:
   ```bash
   kubectl get svc -n <namespace> | grep trino
   ```

3. Verify the post-install hook completed successfully:
   ```bash
   kubectl get jobs -n <namespace> | grep patch-hue-configmap
   kubectl logs job/<release-name>-patch-hue-configmap-<revision> -n <namespace>
   ```

4. Check the Hue ConfigMap contains the Trino interpreter:
   ```bash
   kubectl get configmap hue-config -n <namespace> -o yaml | grep -A 5 trino
   ```

5. If using a custom Trino service name, ensure it's correctly set in `values.yaml`:
   ```yaml
   hue:
     trino:
       serviceName: "your-trino-service-name"
   ```

6. If the hook failed, you can manually trigger it by checking the job logs or re-running the upgrade:
   ```bash
   helm upgrade <release-name> . -n <namespace>
   ```

### Authentication Issues

If you're using LDAP authentication, ensure the credentials are correctly set in `values.yaml`:

```yaml
hue:
  trino:
    auth_username: "your-username"
    auth_password: "your-password"
```

For unsecured connections, leave both fields empty.

## Uninstallation

To uninstall the chart:

```bash
helm uninstall trino-hue --namespace <namespace>
```

## References

- [Trino Helm Chart](https://github.com/trinodb/charts)
- [Apache Hue Helm Chart](https://github.com/cloudera/hue/tree/master/tools/kubernetes/helm)
- [Hue Trino Integration Guide](https://gethue.com/blog/2024-06-26-integrating-trino-editor-in-hue-supporting-data-mesh-and-sql-federation/)

