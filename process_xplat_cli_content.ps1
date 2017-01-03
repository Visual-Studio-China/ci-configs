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
$git_prefix = 'https://github.com/' + $env:APPVEYOR_REPO_NAME + '/blob/'


Function GetReferenceToc
{
  DoGetReferenceToc $root_path 0
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
  ls $folder_path *.yml | ? {$_.BaseName -ne "toc"} | % {
    ac $toc_path ($pre + "- name: " + ($_.BaseName))
    ac $toc_path ($pre + "  href: " + (Resolve-Path $_.FullName -Relative))
    $sub_path = Join-Path $folder_path $_.BaseName
    if(Test-Path $sub_path)
    {
      ac $toc_path ($pre+ "  items:")
      DoGetReferenceToc $sub_path ($level + 1)
    }
  }
}

Function GetJsFilePath
{
  param([string]$file_path)
  
  $all = gc $file_path | Out-String | sls "filePath:.*js" -AllMatches | % matches | % {$_ -replace "filePath:\s*", ""}
  if($all -eq $null -or $all.count -eq 0)
  {
    return $null
  }
  $js_path = $all[0]
  foreach($t in $all)
  {
    if($t -ne $js_path)
    {
      return $null
    }
  }
  return $js_path
}

Function AssembleMetadata
{
  param([string]$metadata, [string]$key, [string]$value)
  
  if([string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($value))
  {
    return $metadata
  }
  return ($metadata + "  " + $key + ": " + $value + "`r`n")
}

Function ProcessReferenceFiles
{
  param([string]$path)
  
  $metadata = "Metadata:" + "`r`n"
  $metadata = AssembleMetadata $metadata "ms.topic" "reference"
  $js_path = GetJsFilePath $path
  if($js_path -eq $null)
  {
    $metadata = AssembleMetadata $metadata "open_to_public_contributors" "false"
  }
  else
  {
    $metadata = AssembleMetadata $metadata "open_to_public_contributors" "true"
    $git_url = (New-Object System.Uri ($git_prefix + $env:APPVEYOR_REPO_BRANCH + '/lib/' + $js_path)).AbsoluteUri
    $metadata = AssembleMetadata $metadata "content_git_url" $git_url
    $metadata = AssembleMetadata $metadata "original_content_git_url" $git_url    
    $js_full_path = Join-Path $env:APPVEYOR_BUILD_FOLDER "lib\$js_path"
    cd (split-path $js_full_path -parent)
    $date = (Get-Date (git log --pretty=format:%cd -n 1 --date=iso $js_full_path)).ToUniversalTime()
    $metadata = AssembleMetadata $metadata "update_at" (Get-Date $date -format g)
    $metadata = AssembleMetadata $metadata "ms.date" (Get-Date $date -format d)
    $git_commit = (New-Object System.Uri ($git_prefix + (git rev-list -1 HEAD $js_full_path) + '/lib/' + $js_path)).AbsoluteUri
    $metadata = AssembleMetadata $metadata "gitcommit" $git_commit
  }
  
  $metadata = AssembleMetadata $metadata 'ms.prod' ${env:prod}
  $metadata = AssembleMetadata $metadata 'ms.technology' ${env:technology}
  $metadata = AssembleMetadata $metadata 'author' ${env:author}
  $metadata = AssembleMetadata $metadata 'ms.author' ${env:ms.author}
  $metadata = AssembleMetadata $metadata 'keywords' ${env:keywords}
  $metadata = AssembleMetadata $metadata 'manager' ${env:manager}

  ac $path $metadata
}

Function SetMetadata
{
  param([string]$header, [string]$new_header, [string]$key, [string]$value, [bool]$overwrite)
  
  if([string]::IsNullOrWhiteSpace($value))
  {
    return $new_header
  }
  $meta = "(?m)^$key\s*:[\s\S].*"
  if($header -match $meta -and $overwrite)
  {
    $new_header = $new_header.replace($matches[0], $key + ': ' + $value)
  }
  if($header -notmatch $meta)
  {
    $new_header = $new_header + $key + ': ' + $value + "`r`n"
  }
  return $new_header
}

Function ProcessConceptualFiles
{
  param([string]$path)
  
  $header_pattern = "^(?s)\s*[-]{3}(.*?)[-]{3}\r?\n"
  $valid_header = $true
  if((gc $path | Out-String) -match $header_pattern)
  {
    $header = $matches[1]
    $new_header = $matches[1]
  }
  else
  {
    $valid_header = $false
    $header = ""
    $new_header = ""
  }
  $file_rel_path = $path -replace ".*$root_name", "/$root_name" -replace "\\", "/" -replace ".*Conceptual","/Documentation"
  $file_full_path = Join-Path $env:APPVEYOR_BUILD_FOLDER $file_rel_path
  cd (Split-Path $file_full_path -parent)
  $date = (Get-Date (git log --pretty=format:%cd -n 1 --date=iso $file_full_path)).ToUniversalTime()
  $new_header = SetMetadata $header $new_header 'updated_at' (Get-Date $date -format g) $true
  $new_header = SetMetadata $header $new_header 'ms.date' (Get-Date $date -format d) $true
  $content_git_url = (New-Object System.Uri ($git_prefix + $env:APPVEYOR_REPO_BRANCH + $file_rel_path)).AbsoluteUri
  $new_header = SetMetadata $header $new_header 'content_git_url' $content_git_url  $true
  $new_header = SetMetadata $header $new_header 'original_content_git_url' $content_git_url  $true

  $git_commit_url = (New-Object System.Uri ($git_prefix + (git rev-list -1 HEAD $file_full_path) + $file_rel_path)).AbsoluteUri
  $new_header = SetMetadata $header $new_header 'gitcommit' $git_commit_url  $true

  $new_header = SetMetadata $header $new_header 'ms.topic: conceptual'
  $new_header = SetMetadata $header $new_header 'ms.prod' ${env:prod}
  $new_header = SetMetadata $header $new_header 'ms.technology' ${env:technology}
  $new_header = SetMetadata $header $new_header 'author' ${env:author}
  $new_header = SetMetadata $header $new_header 'ms.author' ${env:ms.author}
  $new_header = SetMetadata $header $new_header 'keywords' ${env:keywords}
  $new_header = SetMetadata $header $new_header 'manager' ${env:manager}
  $new_header = SetMetadata $header $new_header 'ms.service' ${env:manager}
  $new_header = SetMetadata $header $new_header 'open_to_public_contributors' 'true'

  if($header -ne $new_header)
  {
    if($valid_header)
    {
      sc $path (gc $path | Out-String).replace($header, $new_header) -NoNewline
    }
    else
    {
      sc $path ("---" + "`r`n" + $new_header + "---" + "`r`n" + (gc $path | Out-String)) -NoNewline
    }
  }
}
Function ProcessFiles
{
  ls $root_path *.yml -r | ? {$_.BaseName -ne 'toc'} | % {ProcessReferenceFiles $_.FullName}
  ls $root_path -dir | ? {$_.BaseName -eq "Conceptual"} | % {ls $_.FullName *.md -r} | % {ProcessConceptualFiles $_.FullName}
}

echo "generate toc..."
cd $root_path
if(Test-Path $toc_path)
{
  rm $toc_path
}
ni $toc_path
GetConceptualToc
GetReferenceToc

echo "completed successfully"

echo "process files..."
ProcessFiles
echo "completed successfully"