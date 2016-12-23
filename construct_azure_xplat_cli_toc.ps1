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
$toc_path = Join-Path $root_path "toc.yml"


Function GetReferenceToc
{
  ls $root_path -dir | ?{$_.Name -ne "Conceptual"} | % {DoGetReferenceToc $_.FullName 0} 
  sc $toc_path (gc $toc_path | Out-String).replace("\", "/") -NoNewline
}

Function GetConceptualToc
{
  $conceptual = Join-Path $root_path "Conceptual"
  if(Test-Path $conceptual)
  {
    ac $toc_path "- name: Conceptual"
    ac $toc_path "  items:"
    DoGetConceptualToc $conceptual 1
  }
}

Function global:DoGetConceptualToc
{
  param([string]$folder_path, [int]$level)

  $pre = ""

  for($i=0;$i -lt $level;$i++)
  {
    $pre = $pre + "    "
  }
  ls $folder_path *.md | % {
    ac $toc_path ($pre + "- name: " + $_.BaseName)
    ac $toc_path ($pre + "  href: " + (Resolve-Path $_.FullName -Relative))
    }
  
  $sub_folders = ls $folder_path -dir
  if($sub_folders -ne $null)
  {
    ac $toc_path ($pre + "  items:")
	$sub_folders | % {DoGetConceptualToc $_.FullName ($level + 1)}
  }
}

Function global:DoGetReferenceToc
{
  param([string]$folder_path, [int]$level)

  $pre = ""

  for($i=0;$i -lt $level;$i++)
  {
    $pre = $pre + "    "
  }
  
  ac $toc_path ($pre + "- name: " + (Split-Path $folder_path -Leaf))
  ac $toc_path ($pre + "  href: " + (Resolve-Path (ls $folder_path *.xyml | select -First 1).FullName -Relative))
  
  $sub_folders = ls $folder_path -dir
  if($sub_folders -ne $null)
  {
    ac $toc_path ($pre + "  items:")
	$sub_folders | % {DoGetReferenceToc $_.FullName ($level + 1)}
  }
}

echo "generate toc..."
if(Test-Path $toc_path)
{
  rm $toc_path
}
ni $toc_path
GetConceptualToc
GetReferenceToc

echo "completed successfully."