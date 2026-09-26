# ============================================================
# Start 3.0 (Flutter) —— 构建脚本
# 流程: 写 keystore.properties -> flutter build apk --release -> 校验 -> 改名
# 需要环境变量:
#   START_KS_PASS  签名密钥密码（默认 A716825start）
# ============================================================
param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path

# Flutter 与 Git 路径（可用环境变量覆盖）
$env:PATH = "$(if ($env:START_FLUTTER) { $env:START_FLUTTER } else { 'D:\flutter' })\bin;$(if ($env:START_GIT) { $env:START_GIT } else { 'D:\Git' })\cmd;$env:PATH"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = Join-Path (Split-Path -Parent $ROOT) "Astart\tools\jdk-17.0.20.1+1" }
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

$KS_PASS = if ($env:START_KS_PASS) { $env:START_KS_PASS } else { 'A716825start' }

# 由 gradle 读取，文件不入库（.gitignore 已排除）
$ksProps = Join-Path $ROOT "android\keystore.properties"
@"
storeFile=key.jks
storePassword=$KS_PASS
keyAlias=start
keyPassword=$KS_PASS
"@ | Set-Content -Path $ksProps -Encoding ASCII -NoNewline

if (-not (Test-Path (Join-Path $ROOT "android\app\key.jks"))) {
    throw "缺少 android\app\key.jks（RSA 2048，alias=start），请先放好签名密钥"
}

if ($Clean) { flutter clean }

Set-Location $ROOT
flutter pub get
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "构建失败" }

$srcApk = Join-Path $ROOT "build\app\outputs\flutter-apk\app-release.apk"
$outApk = Join-Path $ROOT "Start-2.0-signed.apk"
Copy-Item $srcApk $outApk -Force

# 校验签名（v2/v3）与权限（不得出现 INTERNET）
$BT = Join-Path (Split-Path -Parent $ROOT) "Astart\sdk\build-tools\34.0.0"
& (Join-Path $BT "apksigner.bat") verify -v $outApk
$badging = & (Join-Path $BT "aapt2.exe") dump badging $outApk
$badging | Select-String "^package:"
$internet = $badging | Select-String "android.permission.INTERNET"
if ($internet) { throw "检测到 INTERNET 权限，违反不联网约束！" }
Write-Host "完成: $outApk"
