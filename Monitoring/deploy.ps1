# ================================================================
# deploy.ps1
# Grafana Observability Stack for Amazon EKS
#
# Components:
#   - Prometheus
#   - Loki
#   - Alloy
#   - Grafana
#
# Storage:
#   - Loki -> Amazon S3
#   - Grafana -> EBS PVC
#   - Prometheus -> EBS PVC
#
# Authentication:
#   - Loki -> AWS IAM Role / IRSA
#
# Target:
#   EKS cluster
# ================================================================

$ErrorActionPreference = "Stop"

# ================================================================
# Configuration
# ================================================================

$AWS_REGION       = "ap-south-1"
$CLUSTER_NAME     = "my-cluster"

$MONITORING_NS    = "monitoring"

# Change this to your actual globally-unique S3 bucket name
$S3_BUCKET = "prod-akashdev-loki-logs-3328"

# IAM role used by Loki through IRSA
$LOKI_ROLE_NAME   = "loki-s3-role"

# IAM policy name
$LOKI_POLICY_NAME = "LokiS3Policy"

# Helm chart versions
$PROMETHEUS_CHART_VERSION = "67.4.0"
$LOKI_CHART_VERSION        = "6.29.0"
$ALLOY_CHART_VERSION       = "0.12.0"
$GRAFANA_CHART_VERSION     = "8.10.4"


# ================================================================
# Helper functions
# ================================================================

function Log {
    param([string]$Message)

    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Step {
    param([string]$Message)

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor DarkGray
    Write-Host "[STEP] $Message" -ForegroundColor Yellow
    Write-Host "============================================================" `
        -ForegroundColor DarkGray
}

function Die {
    param([string]$Message)

    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}


# ================================================================
# Pre-flight checks
# ================================================================

Step "Pre-flight checks"

$requiredCommands = @(
    "kubectl",
    "helm",
    "aws",
    "eksctl"
)

foreach ($command in $requiredCommands) {

    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        Die "$command was not found. Please install it first."
    }

    Log "$command found"
}


# ================================================================
# AWS / Kubernetes context
# ================================================================

Step "Configuring EKS access"

Log "AWS Region : $AWS_REGION"
Log "Cluster    : $CLUSTER_NAME"
Log "Namespace  : $MONITORING_NS"
Log "S3 Bucket  : $S3_BUCKET"

aws sts get-caller-identity | Out-Null

if ($LASTEXITCODE -ne 0) {
    Die "AWS authentication failed."
}

aws eks update-kubeconfig `
    --region $AWS_REGION `
    --name $CLUSTER_NAME

if ($LASTEXITCODE -ne 0) {
    Die "Failed to configure kubeconfig."
}

Log "Kubeconfig updated"


# ================================================================
# Verify cluster
# ================================================================

Step "Verifying Kubernetes cluster"

kubectl cluster-info

if ($LASTEXITCODE -ne 0) {
    Die "Unable to connect to Kubernetes cluster."
}

kubectl get nodes -o wide


# ================================================================
# Namespaces
# ================================================================

Step "Creating monitoring namespace"

kubectl create namespace $MONITORING_NS `
    --dry-run=client `
    -o yaml |
    kubectl apply -f -

Log "Namespace ready"


# ================================================================
# Check whether S3 bucket already exists
# ================================================================

Step "Checking S3 bucket"

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"

$bucketOutput = & aws s3api head-bucket `
    --bucket $S3_BUCKET `
    --region $AWS_REGION 2>&1

$bucketExitCode = $LASTEXITCODE

$ErrorActionPreference = $oldErrorActionPreference

if ($bucketExitCode -eq 0) {

    Log "S3 bucket already exists: $S3_BUCKET"

}
else {

    Log "S3 bucket does not exist. Creating: $S3_BUCKET"

    & aws s3api create-bucket `
        --bucket $S3_BUCKET `
        --region $AWS_REGION `
        --create-bucket-configuration LocationConstraint=$AWS_REGION

    if ($LASTEXITCODE -ne 0) {
        Die "Failed to create S3 bucket."
    }

    Log "S3 bucket created: $S3_BUCKET"
}


# ================================================================
# Block public access
# ================================================================

Step "Securing S3 bucket"

aws s3api put-public-access-block `
    --bucket $S3_BUCKET `
    --public-access-block-configuration `
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true `
    --region $AWS_REGION

Log "S3 public access blocked"


# ================================================================
# S3 Lifecycle
# ================================================================

Step "Configuring S3 lifecycle policy"

$lifecycleConfig = @"
{
  "Rules": [
    {
      "ID": "loki-log-expiry",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": {
        "Days": 30
      },
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 7
      }
    }
  ]
}
"@

$lifecycleFile = Join-Path $env:TEMP "loki-lifecycle.json"

Set-Content `
    -Path $lifecycleFile `
    -Value $lifecycleConfig

aws s3api put-bucket-lifecycle-configuration `
    --bucket $S3_BUCKET `
    --lifecycle-configuration file://$lifecycleFile `
    --region $AWS_REGION

Remove-Item $lifecycleFile -Force -ErrorAction SilentlyContinue

Log "S3 lifecycle policy configured"


# ================================================================
# IAM Policy
# ================================================================

Step "Creating Loki S3 IAM policy"

$policyTemplate = Join-Path $PSScriptRoot "05-loki-s3-iam-policy.json"

if (-not (Test-Path $policyTemplate)) {
    Die "05-loki-s3-iam-policy.json was not found."
}

$policyDocument = Get-Content `
    $policyTemplate `
    -Raw

$policyDocument = $policyDocument.Replace(
    "<YOUR_S3_BUCKET>",
    $S3_BUCKET
)

$policyFile = Join-Path $env:TEMP "loki-s3-policy.json"

Set-Content `
    -Path $policyFile `
    -Value $policyDocument


# ================================================================
# Check whether IAM policy exists
# ================================================================

$accountId = aws sts get-caller-identity `
    --query Account `
    --output text

$policyArn = "arn:aws:iam::$accountId`:policy/$LOKI_POLICY_NAME"

# ================================================================
# Check whether IAM policy exists
# ================================================================

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"

$policyCheck = & aws iam get-policy `
    --policy-arn $policyArn 2>&1

$policyExitCode = $LASTEXITCODE

$ErrorActionPreference = $oldErrorActionPreference

if ($policyExitCode -eq 0) {

    Log "IAM policy already exists: $LOKI_POLICY_NAME"

}
else {

    Log "IAM policy does not exist. Creating: $LOKI_POLICY_NAME"

    & aws iam create-policy `
        --policy-name $LOKI_POLICY_NAME `
        --policy-document file://$policyFile

    if ($LASTEXITCODE -ne 0) {
        Die "Failed to create IAM policy."
    }

    Log "IAM policy created: $LOKI_POLICY_NAME"
}


# ================================================================
# OIDC / IRSA
# ================================================================

Step "Configuring IRSA for Loki"

$oidcProvider = aws eks describe-cluster `
    --name $CLUSTER_NAME `
    --region $AWS_REGION `
    --query "cluster.identity.oidc.issuer" `
    --output text

if (-not $oidcProvider) {
    Die "Unable to retrieve EKS OIDC provider."
}

Log "OIDC provider detected"


# ================================================================
# Check whether Loki IAM role already exists
# ================================================================

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"

$existingRole = & aws iam get-role `
    --role-name $LOKI_ROLE_NAME `
    2>&1

$roleExitCode = $LASTEXITCODE

$ErrorActionPreference = $oldErrorActionPreference

if ($roleExitCode -eq 0) {

    Log "Loki IAM role already exists: $LOKI_ROLE_NAME"

}
else {

    Log "Loki IAM role does not exist. Creating through eksctl"

    & eksctl create iamserviceaccount `
        --cluster $CLUSTER_NAME `
        --region $AWS_REGION `
        --namespace $MONITORING_NS `
        --name loki `
        --role-name $LOKI_ROLE_NAME `
        --attach-policy-arn $policyArn `
        --approve `
        --override-existing-serviceaccounts

    if ($LASTEXITCODE -ne 0) {
        Die "Failed to create Loki IAM service account."
    }

    Log "Loki IAM service account created: $LOKI_ROLE_NAME"
}

$LOKI_ROLE_ARN = aws iam get-role `
    --role-name $LOKI_ROLE_NAME `
    --query "Role.Arn" `
    --output text

Log "Loki IAM role: $LOKI_ROLE_ARN"


# ================================================================
# Helm repositories
# ================================================================

Step "Adding Helm repositories"

helm repo add prometheus-community `
    https://prometheus-community.github.io/helm-charts `
    2>$null

helm repo add grafana `
    https://grafana.github.io/helm-charts `
    2>$null

helm repo add grafana-community `
    https://grafana-community.github.io/helm-charts `
    2>$null

helm repo update

Log "Helm repositories updated"


# ================================================================
# Loki values - inject IRSA role
# ================================================================

# ================================================================
# Loki configuration
# ================================================================

Step "Preparing Loki configuration"

$lokiValues = Join-Path $PSScriptRoot "02-loki-values.yaml"

if (-not (Test-Path $lokiValues)) {
    Die "02-loki-values.yaml was not found."
}

# Create temporary copy so the repository file remains unchanged.
$lokiValuesTemp = Join-Path $env:TEMP "02-loki-values-patched.yaml"

$lokiContent = Get-Content $lokiValues -Raw

# Inject environment-specific S3 bucket.
$lokiContent = $lokiContent.Replace(
    "YOUR_S3_BUCKET",
    $S3_BUCKET
)

# Inject the IRSA role created by eksctl.
$lokiContent = $lokiContent.Replace(
    "ROLE_ARN_PLACEHOLDER",
    $LOKI_ROLE_ARN
)

Set-Content `
    -Path $lokiValuesTemp `
    -Value $lokiContent `
    -Encoding UTF8

if (-not (Test-Path $lokiValuesTemp)) {
    Die "Failed to create patched Loki values file."
}

Log "Loki values prepared"


# ================================================================
# Prometheus
# ================================================================

Step "1/4 Installing Prometheus"

helm upgrade --install prometheus `
    prometheus-community/kube-prometheus-stack `
    --namespace $MONITORING_NS `
    --values (Join-Path $PSScriptRoot "01-prometheus-values.yaml") `
    --version $PROMETHEUS_CHART_VERSION `
    --wait `
    --timeout 10m

if ($LASTEXITCODE -ne 0) {
    Die "Prometheus installation failed."
}

Log "Prometheus installed"


# ================================================================
# Loki
# ================================================================

Step "2/4 Installing Loki"

helm upgrade --install loki `
    grafana-community/loki `
    --namespace $MONITORING_NS `
    --values $lokiValuesTemp `
    --version $LOKI_CHART_VERSION `
    --wait `
    --timeout 10m

if ($LASTEXITCODE -ne 0) {
    Die "Loki installation failed."
}

Log "Loki installed"


# ================================================================
# Alloy
# ================================================================

Step "3/4 Installing Grafana Alloy"

helm upgrade --install alloy `
    grafana/alloy `
    --namespace $MONITORING_NS `
    --values (Join-Path $PSScriptRoot "03-alloy-values.yaml") `
    --version $ALLOY_CHART_VERSION `
    --wait `
    --timeout 10m

if ($LASTEXITCODE -ne 0) {
    Die "Alloy installation failed."
}

Log "Grafana Alloy installed"


# ================================================================
# Grafana
# ================================================================
# ================================================================
# Grafana Admin Secret
# ================================================================

Step "Creating Grafana admin secret"

$grafanaAdminUser = "admin"

$grafanaAdminPassword = Read-Host `
    "Enter Grafana admin password" `
    -AsSecureString

$grafanaAdminPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $grafanaAdminPassword
    )
)

kubectl create secret generic grafana-admin-secret `
    --namespace $MONITORING_NS `
    --from-literal=admin-user=$grafanaAdminUser `
    --from-literal=admin-password=$grafanaAdminPasswordPlain `
    --dry-run=client `
    -o yaml |
    kubectl apply -f -

$grafanaAdminPasswordPlain = $null

Log "Grafana admin secret is ready"

Step "4/4 Installing Grafana"

helm upgrade --install grafana `
    grafana/grafana `
    --namespace $MONITORING_NS `
    --values (Join-Path $PSScriptRoot "04-grafana-values.yaml") `
    --version $GRAFANA_CHART_VERSION `
    --wait `
    --timeout 10m

if ($LASTEXITCODE -ne 0) {
    Die "Grafana installation failed."
}

Log "Grafana installed"


# ================================================================
# Verification
# ================================================================

Step "Verifying monitoring stack"

Log "Pods:"
kubectl get pods -n $MONITORING_NS -o wide

Write-Host ""

Log "Services:"
kubectl get svc -n $MONITORING_NS

Write-Host ""

Log "PersistentVolumeClaims:"
kubectl get pvc -n $MONITORING_NS

Write-Host ""

Log "ServiceMonitors:"
kubectl get servicemonitor -n $MONITORING_NS `
    2>$null


# ================================================================
# Helm releases
# ================================================================

Step "Checking Helm releases"

helm list -n $MONITORING_NS


# ================================================================
# Final status
# ================================================================

Step "Deployment completed"

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Green

Write-Host " Monitoring stack deployed successfully" `
    -ForegroundColor Green

Write-Host "============================================================" `
    -ForegroundColor Green

Write-Host ""

Log "Namespace : $MONITORING_NS"
Log "Cluster   : $CLUSTER_NAME"
Log "Region    : $AWS_REGION"
Log "S3 Bucket : $S3_BUCKET"

Write-Host ""

Log "Useful commands:"

Write-Host "kubectl get pods -n $MONITORING_NS"
Write-Host "kubectl get svc -n $MONITORING_NS"
Write-Host "helm list -n $MONITORING_NS"
Write-Host "kubectl get ingress -n $MONITORING_NS"

Write-Host ""

Log "Monitoring deployment finished."
