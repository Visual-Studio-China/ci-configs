<#
.SYNOPSIS
    This is a Powershell script to process files and generate a toc file.
.DESCRIPTION
    This script is used in specific ci projects(appveyor.yml) and depends on both
    APPVEYOR built-in environment variables and the ones defined in those projects.
    We didn't decouple it cause we want to keep the update as more as possible in this
    script instead of in the appveyor.yml.
#>

# Validate that the repo has only one root folder
if((Get-ChildItem $env:APPVEYOR_BUILD_FOLDER -dir).count -ne 1)
{
  $host.SetShouldExit(-1)
}

$header_pattern = "^(?s)\s*[-]{3}(.*?)[-]{3}\r?\n"
$landing_page_pattern = "Module\s*Name\s*:"
$root_path = (Get-ChildItem $env:APPVEYOR_BUILD_FOLDER -dir | Select-Object -First 1).FullName
$root_name = Split-Path $root_path -Leaf
$toc_path = Join-Path $root_path "toc.yml"


Function global:DoGetToc
{
  param([string]$folder_path, [int]$level)

  $pre = ""

  for($i=0;$i -lt $level;$i++)
  {
    $pre = $pre + "    "
  }
  
  Add-Content $toc_path ($pre + "- name: " + (Split-Path $folder_path -Leaf))
  $index = Get-ChildItem $folder_path | ? {$_.Name -eq 'index.md'} | Select-Object -ExpandProperty FullName
  if($index -ne $null)
  {
    Add-Content $toc_path ($pre + "  href: " + ($index -replace ".*$root_name", ".."))
  }
  
  $sub_folders = Get-ChildItem $folder_path -dir
  if($sub_folders -eq $null)
  {
    $files = Get-ChildItem $folder_path *.md | Select-Object -ExpandProperty FullName
    $landing_page = ""
    $files | ? {(Get-Content $_ | Out-String) -match $header_pattern -and $matches[1] -match $landing_page_pattern} | Select-Object -First 1 | % {
      Add-Content $toc_path ($pre + "  href: " + ($_ -replace ".*$root_name", ".."))
      $landing_page = $_
    }

    Add-Content $toc_path ($pre + "  items:")
    $pre = $pre + "    "
    $files | ? {$_ -ne $landing_page} | % {
      Add-Content $toc_path ($pre + "- name: " + (Get-Item $_).BaseName + "`r`n" + $pre + "  href: " + ($_ -replace ".*$root_name", ".."))
    }
  }
  else
  {
    Add-Content $toc_path ($pre + "  items:")
    Get-ChildItem $folder_path *.md | ? {$_.Name -ne "index.md"} | Select-Object -ExpandProperty FullName | % {
      Add-Content $toc_path ($pre + "    - name: " + (Get-Item $_).BaseName + "`r`n" + $pre + "      href: " + ($_ -replace ".*$root_name", ".."))
    }

    if(($sub_folders | Select-Object -First 1).Name -match 'v\d(.\d)*')
    {
      $sub_folders = $sub_folders | Sort-Object -Property @{
        Expression = {
          $version = $_.Name.replace('v', '')
          if($version  -match '^\d$')
          {
            $version = $version + '.0'
          }
          New-Object System.Version $version
        };Ascending = $False
      }
    }
    $sub_folders | % {DoGetToc $_.FullName ($level + 1)}
  }
}

$script_block =
{
  param([string]$file, [string]$root_path, [string]$pattern, [string]$landing_page_pattern)

  $related_link_pattern = "#*\s*RELATED\s*LINKS\s*(.|\n)*"
  $platyPS_file = $true
  $root_name = Split-Path $root_path -Leaf

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

  # remove empty header first
  sc $file ((Get-Content $file | Out-String) -replace "-{3}(\r?\n)+-{3}", "") -NoNewline

  if((Get-Content $file | Out-String) -match $pattern)
  {
    $header = $matches[1]
    $new_header = $matches[1]
  }
  else
  {
    $platyPS_file = $false
    $header = ""
    $new_header = ""
  }
  # need to get git log info and resolve relative path
  Set-Location (Split-Path $file -parent)

  # set or update metadata in the header of .md files
  $date = (Get-Date (git log --pretty=format:%cd -n 1 --date=iso $file)).ToUniversalTime()
  $new_header = SetMetadata $header $new_header 'updated_at' (Get-Date $date -format g) $true
  $new_header = SetMetadata $header $new_header 'ms.date' (Get-Date $date -format d) $true

  $file_rel_path = $file -replace ".*$root_name", "/$root_name" -replace "\\", "/"
  $git_prefix = 'https://github.com/' + $env:APPVEYOR_REPO_NAME + '/blob/'
  $content_git_url = (New-Object System.Uri ($git_prefix + $env:APPVEYOR_REPO_BRANCH + $file_rel_path)).AbsoluteUri
  $new_header = SetMetadata $header $new_header 'content_git_url' $content_git_url  $true
  $new_header = SetMetadata $header $new_header 'original_content_git_url' $content_git_url  $true

  $git_commit_url = (New-Object System.Uri ($git_prefix + (git rev-list -1 HEAD $file) + $file_rel_path)).AbsoluteUri
  $new_header = SetMetadata $header $new_header 'gitcommit' $git_commit_url  $true

  $topic_type = 'reference'
  if(!$platyPS_file -or $header -match $landing_page_pattern)
  {
    $topic_type = 'conceptual'
    if((Split-Path $file -Leaf) -ne "index.md")
    {
      $new_header = SetMetadata $header $new_header 'uid' ($file_rel_path.split('/',3) | Select-Object -Last 1) $true
    }
  }
  
  $new_header = SetMetadata $header $new_header 'ms.topic' $topic_type $true
  $new_header = SetMetadata $header $new_header 'ms.prod' $env:prod
  $new_header = SetMetadata $header $new_header 'ms.technology' $env:technology
  $new_header = SetMetadata $header $new_header 'author' $env:author
  $new_header = SetMetadata $header $new_header 'ms.author' ${env:ms.author}
  $new_header = SetMetadata $header $new_header 'keywords' $env:keywords
  $new_header = SetMetadata $header $new_header 'manager' $env:manager
  $new_header = SetMetadata $header $new_header 'open_to_public_contributors' ($env:open_to_public_contributors -ne 'false')

  $ms_service_file = Join-Path $root_path "ms.service.json"
  $service = ""
  if(Test-Path $ms_service_file)
  {
    $ms_service = (Get-Content $ms_service_file -raw) | ConvertFrom-Json
    $service = $ms_service.($file_rel_path.split('/')[2]).($file_rel_path.split('/')[3])
  }
  if([string]::IsNullOrWhiteSpace($service))
  {
    $service = $env:service
  }
  $new_header = SetMetadata $header $new_header 'ms.service' $service

  if($platyPS_file)
  {
    # reduce unnecessary file write
    if($header -ne $new_header)
    {
      Set-Content $file (Get-Content $file | Out-String).replace($header, ($new_header -replace "{|}", "")) -NoNewline
    }

    # resolve related links to the format that docfx supports [link name](xref:uid)
    if((Get-Content $file | Out-String) -match $related_link_pattern)
    {
      $related_links = $matches[0]
      $new_related_links = $matches[0]
      $related_links | Select-String "\[\S.*\]\(.*\)" -AllMatches | % matches | ? {$_ -match "\(.*.md\s*\)" -and $_ -notmatch "xref:"} | % {
        $rel_path = (Resolve-Path ($matches[0] -replace "\(|\)", "")) -replace ".*$root_name", "" -replace "\\", "/"
        $value = "(xref:" + $rel_path.Substring(1, $rel_path.LastIndexOf('/'))
        $new_related_links = $new_related_links.replace($_, ($_ -replace "\\", "/" -replace "\(.*/", $value))
      }
    }
    if($related_links -ne $new_related_links)
    {
      Set-Content $file (Get-Content $file | Out-String).replace($related_links, $new_related_links) -NoNewline
    }
  }
  else
  {
    Set-Content $file ("---" + "`r`n" + $new_header + "---" + "`r`n" + (Get-Content $file | Out-String)) -NoNewline
  }
}
Function ProcessFiles
{
  $max_threads = 8
  $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $max_threads)
  $RunspacePool.Open()
  $Jobs = @()
  Get-ChildItem $root_path -r "*.md" | % {
    $Job = [powershell]::Create().AddScript($script_block).AddArgument($_.FullName).AddArgument($root_path).AddArgument($header_pattern).AddArgument($landing_page_pattern)
    $Job.RunspacePool = $RunspacePool
    $Jobs += New-Object PSObject -Property @{
      RunNum = $_.FullName
      Pipe = $Job
      Result = $Job.BeginInvoke()
    }
  }
  Do
  {
    Start-Sleep -Seconds 5
  } While ($Jobs.Result.IsCompleted -contains $false)
}

# Step 1: process .md files
echo "Process files ..."
ProcessFiles

# Step 2: generate toc.yml
echo "generate toc..."
if(Test-Path $toc_path)
{
  Remove-Item $toc_path
}
New-Item $toc_path
Get-ChildItem $root_path -dir | % {DoGetToc $_.FullName 0}
Set-Content $toc_path (Get-Content $toc_path | Out-String).replace("\", "/") -NoNewline

echo "completed successfully."