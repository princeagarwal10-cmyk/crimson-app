$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot 'data\crimson_cloud_config.json'
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$base = $config.supabaseUrl.TrimEnd('/')
$authHeaders = @{ apikey = $config.anonKey; 'Content-Type' = 'application/json' }
$token = Invoke-RestMethod -Method Post -Headers $authHeaders `
  -Body (@{ email = $config.email; password = $config.password } | ConvertTo-Json) `
  -Uri "$base/auth/v1/token?grant_type=password" -TimeoutSec 30
$headers = @{ apikey = $config.anonKey; Authorization = "Bearer $($token.access_token)" }

$storePath = Join-Path $env:APPDATA 'Crimson Catalogue Studio\catalogue_store.json'
$state = Get-Content -Raw -LiteralPath $storePath | ConvertFrom-Json
$uploaded = @{}
$uploadedCount = 0

function Get-SafeName([string]$value) {
  $name = [IO.Path]::GetFileName($value)
  $name = [regex]::Replace($name, '[^A-Za-z0-9._-]', '_')
  $name = [regex]::Replace($name, '_+', '_')
  if ([string]::IsNullOrWhiteSpace($name)) { return 'product_image.jpg' }
  return $name
}

function Get-Mime([string]$path) {
  $lower = $path.ToLowerInvariant()
  if ($lower.EndsWith('.png')) { return 'image/png' }
  if ($lower.EndsWith('.webp')) { return 'image/webp' }
  if ($lower.EndsWith('.bmp')) { return 'image/bmp' }
  return 'image/jpeg'
}

function Upload-Image([string]$path, [string]$productId) {
  if ($uploaded.ContainsKey($path)) { return $uploaded[$path] }
  $fileName = Get-SafeName $path
  $storagePath = "flutter-catalogue/$productId/$fileName"
  $encoded = ($storagePath -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
  $uploadHeaders = @{
    apikey = $config.anonKey
    Authorization = "Bearer $($token.access_token)"
    'x-upsert' = 'true'
    'Content-Type' = Get-Mime $path
  }
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Invoke-WebRequest -UseBasicParsing -Method Post -InFile $path -Headers $uploadHeaders `
        -Uri "$base/storage/v1/object/product-images/$encoded" -TimeoutSec 60 | Out-Null
      $url = "$base/storage/v1/object/public/product-images/$encoded"
      $uploaded[$path] = $url
      $script:uploadedCount++
      return $url
    } catch {
      if ($attempt -eq 3) { throw }
      Start-Sleep -Seconds 2
    }
  }
  throw "Image upload failed: $path"
}

foreach ($product in @($state.products)) {
  $paths = @($product.imagePaths) + @($product.imagePath)
  $replacements = @{}
  foreach ($rawPath in $paths) {
    $path = [string]$rawPath
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if ($path.StartsWith('http://') -or $path.StartsWith('https://')) { continue }
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $replacements[$path] = Upload-Image $path ([string]$product.id)
  }
  if ($replacements.Count -eq 0) { continue }
  if ($replacements.ContainsKey([string]$product.imagePath)) {
    $product.imagePath = $replacements[[string]$product.imagePath]
  }
  $product.imagePaths = @($product.imagePaths | ForEach-Object {
      $key = [string]$_
      if ($replacements.ContainsKey($key)) { $replacements[$key] } else { $key }
    })
}

$payload = $state | ConvertTo-Json -Depth 30 -Compress
$body = @(@{
  workspace_id = if ($config.workspaceId) { $config.workspaceId } else { 'default' }
  payload = ($payload | ConvertFrom-Json)
  updated_at = [DateTime]::UtcNow.ToString('o')
}) | ConvertTo-Json -Depth 30 -Compress
$postHeaders = @{
  apikey = $config.anonKey
  Authorization = "Bearer $($token.access_token)"
  'Content-Type' = 'application/json'
  Prefer = 'resolution=merge-duplicates'
}
Invoke-RestMethod -Method Post -Headers $postHeaders -Body $body `
  -Uri "$base/rest/v1/crimson_catalogue_live?on_conflict=workspace_id" -TimeoutSec 60 | Out-Null
Write-Output "Uploaded $uploadedCount unique product photos and updated the live catalogue."
