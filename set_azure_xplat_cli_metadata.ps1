<#
.SYNOPSIS
    This is a Powershell script to process files and generate a toc file.
.DESCRIPTION
    This script is used in specific ci projects(appveyor.yml) and depends on both
    APPVEYOR built-in environment variables and the ones defined in those projects.
    We didn't decouple it cause we want to keep the update as more as possible in this
    script instead of in the appveyor.yml.
#>

param(
    [string]$root_path
)

if($root_path -eq $null -or !(Test-Path $root_path))
{
  Write-Error "Please enter the root path to construct toc!"
  exit 1
}

$root_name = Split-Path $root_path -Leaf

ls $root_path -dir | ? {$_.BaseName -ne "Conceptual"} | % {ls $_.FullName *.yml -r} | % {
  $pre = "  "
  $path = $_.FullName
  ac $path "Metadata:"
  cd (Split-Path $path -parent)
  $file_rel_path = $path -replace ".*$root_name", "/$root_name" -replace "\\", "/"
  $git_prefix = 'https://github.com/' + $env:APPVEYOR_REPO_NAME + '/blob/'
  $git_url = (New-Object System.Uri ($git_prefix + $env:APPVEYOR_REPO_BRANCH + $file_rel_path)).AbsoluteUri
  ac $path ($pre + "original_content_git_url: " + $git_url)
  ac $path ($pre + "content_git_url: " + $git_url)
  $date = (Get-Date (git log --pretty=format:%cd -n 1 --date=iso $file)).ToUniversalTime()
  ac $path ($pre + "update_at: " + (Get-Date $date -format g))
  ac $path ($pre + "ms.date: " + (Get-Date $date -format d))
  $git_commit = (New-Object System.Uri ($git_prefix + (git rev-list -1 HEAD $path) + $file_rel_path)).AbsoluteUri
  ac $path ($pre + "gitcommit: " + $git_commit)
  }