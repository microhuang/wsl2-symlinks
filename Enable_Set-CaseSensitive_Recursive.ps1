# 允许脚本执行（如果之前没开过）
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process

# 运行脚本
# .\Enable_Set-CaseSensitive_Recursive.ps1 -TargetDir "C:\path\to\your\aosp"

# fsutil.exe file queryCaseSensitiveInfo C:\path\to\your\aosp


param (
    [Parameter(Mandatory=$true)]
    [string]$TargetDir,

    # 添加一个开关参数，仅执行检测
    [switch]$CheckOnly
)

# 检查输入参数是否为空或路径是否存在
if ([string]::IsNullOrWhiteSpace($TargetDir) -or !(Test-Path $TargetDir)) {
    Write-Error "错误：路径 '$TargetDir' 不存在或为空！"
    exit
}

# 获取绝对路径
$rootPath = (Resolve-Path $TargetDir).Path

# 权限检查
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "必须以管理员权限运行此脚本！"
    exit
}


# 用于统计的变量
$global:countDisabled = 0
$global:countEnabled = 0
$global:disabledList = New-Object System.Collections.Generic.List[string]

function Process-CaseSensitive {
    param ([string]$dirPath)

    # 1. 递归处理所有子目录 (深度优先)
    Get-ChildItem -Path $dirPath -Directory -Force | ForEach-Object {
        Process-CaseSensitive $_.FullName
    }

    # 获取当前目录状态
    $status = fsutil.exe file queryCaseSensitiveInfo "$dirPath"
    $isEnabled = ($status -match "已启用" -or $status -match "enabled")

    if ($isEnabled) {
        $global:countEnabled++
    } else {
        $global:countDisabled++
        $global:disabledList.Add($dirPath)

        if ($CheckOnly) {
            Write-Host "[未启用]: $dirPath" -ForegroundColor Yellow
        } else {
            # 如果不是仅检测模式，则执行开启逻辑
            Enable-CaseSensitiveAction -dirPath $dirPath
        }
    }
}

function Enable-CaseSensitiveForDir {
    param ([string]$dirPath)

    # 1. 先递归处理所有子目录 (深度优先)
    Get-ChildItem -Path $dirPath -Directory -Force | ForEach-Object {
        Enable-CaseSensitiveForDir $_.FullName
    }

    Write-Host "正在处理: $dirPath" -ForegroundColor Cyan

    # 检查当前目录是否已经开启大小写敏感
    $status = fsutil.exe file queryCaseSensitiveInfo "$dirPath"
    if ($status -match "已启用" -or $status -match "enabled") {
        Write-Host "跳过（已启用）: $dirPath" -ForegroundColor Gray
    } else {

        # 2. 处理当前目录
        $tempDir = $dirPath + "_tempbak"
        $hasContent = (Get-ChildItem -Path $dirPath -Force).Count -gt 0

        if ($hasContent) {
            # 移动所有内容到临时目录
            if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
            Get-ChildItem -Path $dirPath -Force | Move-Item -Destination $tempDir -Force
        }

        # 3. 开启大小写敏感
        fsutil.exe file setCaseSensitiveInfo "$dirPath" enable

        if ($hasContent) {
            # 移回内容
            Get-ChildItem -Path $tempDir -Force | Move-Item -Destination $dirPath -Force
            Remove-Item $tempDir -Force -Recurse
        }

    }
}

# 开始执行
try {
    if ($CheckOnly) {
        Process-CaseSensitive -dirPath $rootPath
        # 输出最终统计摘要
        Write-Host "`n------------------------------------"
        Write-Host "统计摘要:" -ForegroundColor Cyan
        Write-Host "  已启用目录数: $global:countEnabled" -ForegroundColor Green
        Write-Host "  未启用目录数: $global:countDisabled" -ForegroundColor Yellow
        if ($global:countDisabled -gt 0) {
            if ($CheckOnly) {
                Write-Host "`n检测完成！以上目录需要处理。" -ForegroundColor Yellow
            } else {
                Write-Host "`n全部处理完成！" -ForegroundColor Green
            }
        } else {
            Write-Host "`n完美！所有目录均已处于大小写敏感模式。" -ForegroundColor Green
        }
    } else {
        Enable-CaseSensitiveForDir -dirPath $rootPath
        Write-Host "`n全部完成！整个目录树已启用大小写敏感。" -ForegroundColor Green
    }
} catch {
    Write-Error "处理过程中出错: $_"
}
