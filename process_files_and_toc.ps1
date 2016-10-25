if((ls $env:APPVEYOR_BUILD_FOLDER -Directory).count -ne 1)
{
  $host.SetShouldExit(-1)
}

Write-Host "Begin processing files"
$files = ls $global:root_path -Recurse | ? {$_.extension -eq '.md'} | % { $_.FullName }

$script_block =
{
  param($file, $root_name)
  $pattern = '^(?s)\s*[-]{3}(.*?)[-]{3}\r?\n'
  
  function set_metadata ($header, $new_header, $key, $value, $overwrite)
  {
    if($header -match "$key[\s\S].*" -and $overwrite -eq $true)
    {
      $new_header = $new_header.replace($matches[0], $key + ': ' + $value)
    }
    if($header -notmatch "$key[\s\S].*")
    {
      $new_header = $new_header + $key + ': ' + $value + "`r`n"
    }
    return $new_header
  }
  
  if((gc $file | Out-String) -notmatch $pattern)
  {
    continue
  }
  
  $header = $matches[1]
  $new_header = $matches[1]
  cd $env:APPVEYOR_BUILD_FOLDER

  # set or update metadata
  $date = (Get-Date (git log --pretty=format:%cd -n 1 --date=iso $file)).ToUniversalTime()
  $new_header = set_metadata $header $new_header 'updated_at' (Get-Date $date -format g) $true
  $new_header = set_metadata $header $new_header 'ms.date' (Get-Date $date -format d) $true

  $file_rel_path = $file -replace ".*$root_name", "/$root_name"
  $git_prefix = 'https://github.com/' + $env:APPVEYOR_REPO_NAME + '/blob/'
  $content_git_url = (New-Object System.Uri ($git_prefix + $env:APPVEYOR_REPO_BRANCH + $file_rel_path)).AbsoluteUri
  $new_header = set_metadata $header $new_header 'content_git_url' $content_git_url  $true

  $git_commit_url = (New-Object System.Uri ($git_prefix + (git rev-list -1 HEAD $file) + $file_rel_path)).AbsoluteUri
  $new_header = set_metadata $header $new_header 'gitcommit' $git_commit_url  $true

  $topic_type = 'reference'
  if($header -match 'Module Name')
  {
    $topic_type = 'conceptual'
  }
  
  $new_header = set_metadata $header $new_header 'ms.topic' $topic_type $true
  $new_header = set_metadata $header $new_header 'ms.prod' $env:prod
  $new_header = set_metadata $header $new_header 'ms.service' $env:service
  $new_header = set_metadata $header $new_header 'ms.technology' $env:technology
  $new_header = set_metadata $header $new_header 'author' $env:author
  $new_header = set_metadata $header $new_header 'keywords' $env:keywords
  $new_header = set_metadata $header $new_header 'manager' $env:manager
  $new_header = $new_header.replace('{{', '').replace('}}', '')

  sc $file (gc $file | Out-String).replace($header, $new_header) -NoNewline
}

$MaxThreads = 10
$RunspacePool = [RunspaceFactory ]::CreateRunspacePool(1, $MaxThreads)
$RunspacePool.Open()
$Jobs = @()
$files | % {
  $Job = [powershell]::Create().AddScript($script_block).AddArgument($_).AddArgument($global:root_name)
  $Job.RunspacePool = $RunspacePool
  $Jobs += New-Object PSObject -Property @{
    RunNum = $_
    Pipe = $Job
    Result = $Job.BeginInvoke()
  }
}
    
Write-Host "Waiting..."
Do
{
  Start-Sleep -Seconds 1
} While ($Jobs.Result.IsCompleted -contains $false)
Write-Host "Processing files completed!"

# generate toc
function GetToc
{
  if(Test-Path $toc_path)
  {
    rm $toc_path
  }
  ni $toc_path
  Write-Host "constructing toc..."
  
  foreach($subFolder in (ls $global:root_path -Directory))
  {
    DoGetToc $subFolder.FullName 0
  }
  
  sc $toc_path (gc $toc_path | Out-String).replace('\', '/') -NoNewline
  Write-Host "constructing toc completed."
}

function global:DoGetToc($folder_path, $level)
{
  $pre = ""

  for($i=0;$i -lt $level;$i++)
  {
    $pre = $pre + "    "
  }
  
  ac $toc_path ($pre + "- name: " + (Split-Path $folder_path -Leaf))
  $index = ls $folder_path | ? {$_.Name -eq 'index.md'} | select -ExpandProperty FullName
  if($index -ne $null)
  {
    ac $toc_path ($pre + "  href: " + ($index -replace ".*$global:root_name", ".."))
  }
  
  $sub_folders = ls $folder_path -Directory
  if($sub_folders -eq $null)
  {
    $files = (ls $folder_path) | ? { $_.Extension -eq '.md' } | select -ExpandProperty FullName
    $landing_page = ""
    foreach($file in $files)
    {
      $found = (gc $file | Out-String) -match '^(?s)\s*[-]{3}(.*?)[-]{3}\r?\n'
      if($found -and $matches[1] -match 'Module Name')
      {
        ac $toc_path ($pre + "  href: " + ($file -replace ".*$global:root_name", ".."))
        $landing_page = $file
        break
      }
    }

    ac $toc_path ($pre + "  items:")
    $pre = $pre + "    "
    foreach($file in $files)
    {
      if($file -ne $landing_page)
      {
        ac $toc_path ($pre + "- name: " + (gi $file).BaseName)
        ac $toc_path ($pre + "  href: " + ($file -replace ".*$global:root_name", ".."))
      }
    }
  }
  else
  {
    ac $toc_path ($pre + "  items:")
    if($sub_folders[0].Name -match 'v\d(.\d)*')
    {
      $sub_folders = $sub_folders | Sort-Object -Property Name -Descending
    }
    foreach($sub_folder in $sub_folders)
    {
      DoGetToc $sub_folder.FullName ($level+1)
    }
  }
}

GetToc