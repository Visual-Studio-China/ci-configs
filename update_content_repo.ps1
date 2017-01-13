<#
.SYNOPSIS
    This is a Powershell script to copy files and update breadcrumb.json if necessary
.DESCRIPTION
    This script is used in specific ci projects(appveyor.yml) and depending on both
    APPVEYOR built-in environment variables and the ones defined in those projects.
    We didn't decouple it cause we want to keep the update as more as possible in this
    script instead of in the appveyor.yml.
#>

if((Get-ChildItem $env:APPVEYOR_BUILD_FOLDER -dir).count -ne 1)
{
  $host.SetShouldExit(-1)
}

$ErrorActionPreference = 'Stop'

$root_path = (Get-ChildItem $env:APPVEYOR_BUILD_FOLDER -dir | Select-Object -First 1).FullName
$root_name = Split-Path $root_path -Leaf
$target_path = Join-Path $env:TEMP\Azure $env:target_folder

Function CopyFiles
{
  Get-ChildItem $root_path -dir | % {
    $target = Join-Path $target_path (Split-Path $_.FullName -Leaf)
    if(Test-Path $target)
    {
      Remove-Item $target -Recurse -Force
    }
    Copy-Item $_.FullName $target -Recurse -Force
  }

  $toc_folder = Join-Path $target_path $root_name
  if(!(Test-Path $toc_folder))
  {
    New-Item $toc_folder -type Directory
  }

  Copy-Item (Join-Path $root_path "toc.yml") $toc_folder

  if(Join-Path $root_path "index.md" | Test-Path)
  {
    Copy-Item (Join-Path $root_path "index.md") $toc_folder
  }
}

Function UpdateGlobalToc
{
  param([string]$global_toc)
  if(!(Test-Path $global_toc))
  {
    New-Item $global_toc
  }
  if((Get-Content $global_toc | Out-String) -notmatch $root_name)
  {
    Add-Content $global_toc ("- name: " + $root_name)
    if(Join-Path $root_path "index.md" | Test-Path)
    {
      Add-Content $global_toc ("  href: " + $root_name + "/index.md")
    }
    Add-Content $global_toc ("  tocHref: " + $root_name + "/toc.yml")
  }
}

Function UpdateBreadcrumb
{
  param([string]$breadcrumb_path)

  $breadcrumb = (Get-Content -Raw $breadcrumb_path) | ConvertFrom-Json
  $children = $breadcrumb.children
  if($children -ne $null)
  {
    $new_node = $true
    $children.children | ? {$_.href -match $root_name} | Select-Object -First 1 | % {$new_node = $false}
    if($new_node)
    {
      $new_child = New-Object PSObject -Property @{
        href = $children[0].href + $root_name + "/"
        homepage = $children[0].href + $root_name + "/"
        toc_title = $root_name
        level = 3
      }
      if($children.children -eq $null)
      {
        $children | Add-Member -MemberType NoteProperty -Name children -value @($new_child)
      }
      else
      {
        $children.children += $new_child
      }
      # powershell read json array(one object array) issue, have to insert array mark manually
      Set-Content $breadcrumb_path ('[' + ($breadcrumb | ConvertTo-Json -Depth 5) + ']') -NoNewline
    }
  }
}

echo "copy files ..."
CopyFiles

echo "update global toc ..."
UpdateGlobalToc (Join-Path $target_path "toc.yml")

echo "update breadcrumb ..."
UpdateBreadcrumb (Join-Path $target_path "breadcrumb.json")

echo "completed successfully."
