param([switch]$OfficialPackage)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$flutter=Join-Path $workspace 'toolchains\flutter\bin\flutter.bat'
$java=Join-Path $workspace 'toolchains\java\jdk-17.0.20.1+1'
$gradleZip=Join-Path $workspace 'toolchains\gradle-9.3.1-bin.zip'
$wrapper=Join-Path $PSScriptRoot 'android\gradle\wrapper\gradle-wrapper.properties'
$oldWrapper=[IO.File]::ReadAllText($wrapper)
$props=Join-Path $PSScriptRoot 'android\gradle.properties'
$oldProps=[IO.File]::ReadAllText($props)
$oldSideBySide=$env:ORG_GRADLE_PROJECT_tclSideBySide
Push-Location $PSScriptRoot
try {
    $env:JAVA_HOME=$java
    $env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
    $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
    $env:ORG_GRADLE_PROJECT_tclSideBySide=if($OfficialPackage){'false'}else{'true'}
    [IO.File]::WriteAllText($props,($oldProps -replace 'tclSideBySide=.*',('tclSideBySide='+$env:ORG_GRADLE_PROJECT_tclSideBySide)))
    if(Test-Path $gradleZip){
        $uri='file:///'+($gradleZip -replace '\\','/')
        [IO.File]::WriteAllText($wrapper,($oldWrapper -replace 'distributionUrl=.*',"distributionUrl=$uri"))
    }
    & $flutter build apk --release --split-per-abi --target-platform android-arm --build-name 1.0.0 --build-number 1018
    if($LASTEXITCODE -ne 0){throw 'APK build failed'}
    Write-Output (Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk')
} finally {
    [IO.File]::WriteAllText($wrapper,$oldWrapper)
    [IO.File]::WriteAllText($props,$oldProps)
    $env:ORG_GRADLE_PROJECT_tclSideBySide=$oldSideBySide
    Pop-Location
}
