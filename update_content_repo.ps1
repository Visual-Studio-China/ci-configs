<#
.SYNOPSIS
    This is a Powershell script to copy files and update breadcrumb.json if necessary
.DESCRIPTION
    This script is used in specific ci projects(appveyor.yml) and depending on both
    APPVEYOR built-in environment variables and the ones defined in those projects.
    We didn't decouple it cause we want to keep the update as more as possible in this
    script instead of in the appveyor.yml.
#>

# Validate that the repo has only one root folder
if((ls $env:APPVEYOR_BUILD_FOLDER -dir).count -ne 1)
{
  $host.SetShouldExit(-1)
}

$ErrorActionPreference = 'Stop'

$root_path = (ls $env:APPVEYOR_BUILD_FOLDER -dir | select -First 1).FullName
$root_name = Split-Path $root_path -Leaf
$target_path = Join-Path $env:TEMP\Azure $env:target_folder

Function CopyFiles
{
  ls $root_path -dir | % {
    $target = Join-Path $target_path (Split-Path $_.FullName -Leaf)
    if(Test-Path $target)
    {
      rm $target -Recurse -Force
    }
    copy $_.FullName $target -Recurse -Force
  }

  $toc_folder = Join-Path $target_path $root_name
  if(!(Test-Path $toc_folder))
  {
    ni $toc_folder -type Directory
  }

  copy (Join-Path $root_path "toc.yml") $toc_folder

  if(Join-Path $root_path "index.md" | Test-Path)
  {
    copy (Join-Path $root_path "index.md") $toc_folder
  }
}

Function UpdateGlobalToc
{
  param([string]$global_toc)
  if(!(Test-Path $global_toc))
  {
    ni $global_toc
  }
  if((gc $global_toc | Out-String) -notmatch $root_name)
  {
    ac $global_toc ("- name: " + $root_name)
    if(Join-Path $root_path "index.md" | Test-Path)
    {
      ac $global_toc ("  href: " + $root_name + "/index.md")
    }
    ac $global_toc ("  tocHref: " + $root_name + "/toc.yml")
  }
}

Function UpdateBreadcrumb
{
  param([string]$breadcrumb_path)

  $breadcrumb = (gc -Raw $breadcrumb_path) | ConvertFrom-Json
  $children = $breadcrumb.children
  if($children -ne $null)
  {
    $new_node = $true
    $children.children | ? {$_.href -match $root_name} | select -First 1 | % {$new_node = $false}
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
      sc $breadcrumb_path ('[' + ($breadcrumb | ConvertTo-Json -Depth 5) + ']') -NoNewline
    }
  }
}

# Step 1. copy docs, toc and index page(if there is any) to processing repo
echo "copy files ..."
CopyFiles

# Step 2: add current project to toc node if necessary
echo "update global toc ..."
UpdateGlobalToc (Join-Path $target_path "toc.yml")

# Step 3. update breadcrumb if necessary
echo "update breadcrumb ..."
UpdateBreadcrumb (Join-Path $target_path "breadcrumb.json")

echo "completed successfully."
