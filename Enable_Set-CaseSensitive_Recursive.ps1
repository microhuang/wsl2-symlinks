# 允许脚本执行（如果之前没开过）
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process

# 运行脚本
# .\Enable_Set-CaseSensitive_Recursive.ps1 -TargetDir "C:\path\to\your\aosp"

# fsutil.exe file queryCaseSensitiveInfo C:\path\to\your\aos


param (
    [Parameter(Mandatory=$true)]
    [string]$TargetDir
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
    Enable-CaseSensitiveForDir -dirPath $rootPath
    Write-Host "`n全部完成！整个目录树已启用大小写敏感。" -ForegroundColor Green
} catch {
    Write-Error "处理过程中出错: $_"
}
