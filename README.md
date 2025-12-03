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
  # Enable processing of X-Forwarded-For headers for ingress/proxy support
  additionalConfigProperties:
    - http-server.process-forwarded=true
  ingress:
    enabled: true
    className: "nginx"
    hosts:
      - host: "trino.local"
        paths:
          - path: /
            pathType: ImplementationSpecific
```

### Apache Hue Configuration

Hue is automatically configured to connect to Trino through a post-install hook that patches the Hue ConfigMap. The configuration follows the [official Hue Trino integration guide](https://gethue.com/blog/2024-06-26-integrating-trino-editor-in-hue-supporting-data-mesh-and-sql-federation/).

**Image Configuration**: To use a custom Hue image (e.g., with OIDC support), build it with the same name/tag as the original (e.g., `gethue/hue:latest`) and set `pullPolicy: "Never"` to use your local image.

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
  
  # Image configuration for custom Hue image with OIDC support
  # Build your custom image with the same name/tag (e.g., gethue/hue:latest)
  # and set pullPolicy to "Never" to use your local image
  image:
    registry: "gethue"  # Keep same registry/name as original
    tag: "latest"  # Keep same tag as original
    pullPolicy: "Never"  # Use "Never" for local/custom images
  
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

**Via Ingress** (if enabled):
- Default domain: `http://trino.local`
- Ensure your `/etc/hosts` includes: `127.0.0.1 trino.local` (or configure DNS)
- Or use the configured domain from `trino.ingress.hosts[0].host`

**Via Port Forward**:
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

## OIDC Authentication Configuration

Hue supports OIDC authentication via Keycloak. The configuration is automatically injected into `hue.ini` via a post-install hook.

### Basic Configuration

```yaml
hue:
  oidc:
    enabled: true
    keycloak:
      serviceName: "keycloak"  # Keycloak service name in cluster
      namespace: ""  # Empty = same namespace as release
      realm: "master"  # Keycloak realm name
      ingressDomain: "keycloak.local"  # Optional: if Keycloak is accessible via ingress
    clientId: "trino-hue"
    clientSecret: "your-client-secret"
    createUsersOnLogin: true  # Auto-create users on first login
    superuserGroup: "hue_superuser"
    usernameAttribute: "preferred_username"
```

### Keycloak Client Configuration

In your Keycloak realm, ensure the client (`trino-hue`) is configured with:

- **Client Authentication**: `On` (confidential client)
- **Valid Redirect URIs**: `https://hue.local/oidc/callback/*` (or your Hue domain)
- **Web Origins**: `https://hue.local` (or your Hue domain)

The redirect URLs are automatically configured based on `hue.ingress.domain` if not explicitly set.

### Disabling OIDC

To disable OIDC authentication and use default Hue authentication:

```yaml
hue:
  oidc:
    enabled: false
```

## Using Trino in Hue

Once both services are running:

1. Access the Hue web interface (via ingress or port-forward)
2. If OIDC is enabled, you'll be redirected to Keycloak for authentication
3. After authentication, navigate to the Query Editor
4. Select "Trino" as the interpreter
5. Start querying your data sources through Trino

## Troubleshooting

### Trino Ingress Returns 406 Error (X-Forwarded-For Header)

If you see a `406 Not Acceptable` error when accessing Trino via ingress with the message "Server configuration does not allow processing of the X-Forwarded-For header", you need to enable forwarded header processing in Trino.

**Solution**: Ensure `http-server.process-forwarded=true` is set in `trino.additionalConfigProperties`:

```yaml
trino:
  additionalConfigProperties:
    - http-server.process-forwarded=true
```

After updating the configuration, upgrade the Helm release:
```bash
helm upgrade trino-hue . -n <namespace>
```

The Trino coordinator pods will restart with the new configuration.

### OIDC Redirect URI Issue

If the OIDC redirect URI is using an internal URL (e.g., `http://127.0.0.1:8888/oidc/callback/`) instead of your configured domain (e.g., `https://hue.local/oidc/callback/`), the chart automatically configures Hue to use forwarded headers from the ingress.

The patching script adds the following settings to the `[desktop]` section:
- `use_x_forwarded_host=true` - Tells Hue to use the `X-Forwarded-Host` header
- `secure_proxy_ssl_header=X-Forwarded-Proto` - Tells Hue to use the `X-Forwarded-Proto` header for HTTPS detection

Ensure your ingress is configured with:
- `nginx.ingress.kubernetes.io/use-forwarded-headers: "true"` (already configured by default)

After upgrading, restart the Hue deployment to pick up the new configuration.

### OIDC Authentication Error: ModuleNotFoundError

If you see `ModuleNotFoundError: No module named 'mozilla_django_oidc'` when OIDC is enabled, you need to use a custom Hue Docker image with the package pre-installed.

**Solution**: Build a custom Hue image with `mozilla_django_oidc` installed:

1. Create a Dockerfile:
   ```dockerfile
   FROM gethue/hue:latest
   RUN ./build/env/bin/pip install --no-cache-dir mozilla_django_oidc
   ```

2. Build and load the image into your cluster:
   ```bash
   docker build -t hue-with-oidc:latest -f docker/Dockerfile .
   # For Minikube:
   minikube image load hue-with-oidc:latest
   # Or push to a registry accessible by your cluster
   ```

3. Update `values.yaml` to use your custom image:
   ```yaml
   hue:
     image:
       registry: ""  # Empty for local images, or your registry
       tag: "latest"  # Your custom image tag
       pullPolicy: "Never"  # Use "Never" for local images
   ```

4. Upgrade the Helm release:
   ```bash
   helm upgrade trino-hue . -n <namespace>
   ```

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

