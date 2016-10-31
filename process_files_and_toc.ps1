# 1. read the file, set or update the metadata
# 2. resolve related links to format [related link](xref:uid)
# 3. generate toc

if((ls $env:APPVEYOR_BUILD_FOLDER -dir).count -ne 1)
{
  $host.SetShouldExit(-1)
}
$pattern = "^(?s)\s*[-]{3}(.*?)[-]{3}\r?\n"

$script_block =
{
  param($file, $root_name, $pattern)

  function set_metadata($header, $new_header, $key, $value, $overwrite)
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

  (gc $file | Out-String) -match $pattern | Out-Null
  $header = $matches[1]
  $new_header = $matches[1]
  cd $env:APPVEYOR_BUILD_FOLDER

  $date = (Get-Date (git log --pretty=format:%cd -n 1 --date=iso $file)).ToUniversalTime()
  $new_header = set_metadata $header $new_header 'updated_at' (Get-Date $date -format g) $true
  $new_header = set_metadata $header $new_header 'ms.date' (Get-Date $date -format d) $true

  $file_rel_path = $file -replace ".*$root_name", "/$root_name" -replace "\\", "/"
  $git_prefix = 'https://github.com/' + $env:APPVEYOR_REPO_NAME + '/blob/'
  $content_git_url = (New-Object System.Uri ($git_prefix + $env:APPVEYOR_REPO_BRANCH + $file_rel_path)).AbsoluteUri
  $new_header = set_metadata $header $new_header 'content_git_url' $content_git_url  $true

  $git_commit_url = (New-Object System.Uri ($git_prefix + (git rev-list -1 HEAD $file) + $file_rel_path)).AbsoluteUri
  $new_header = set_metadata $header $new_header 'gitcommit' $git_commit_url  $true

  $topic_type = 'reference'
  if($header -match 'Module\s*Name\s*:')
  {
    $topic_type = 'conceptual'
    $new_header = set_metadata $header $new_header 'uid' ($file_rel_path.split('/',3) | select -Last 1) $true
  }
  
  $new_header = set_metadata $header $new_header 'ms.topic' $topic_type $true
  $new_header = set_metadata $header $new_header 'ms.prod' $env:prod
  $new_header = set_metadata $header $new_header 'ms.service' $env:service
  $new_header = set_metadata $header $new_header 'ms.technology' $env:technology
  $new_header = set_metadata $header $new_header 'author' $env:author
  $new_header = set_metadata $header $new_header 'ms.author' ${env:ms.author}
  $new_header = set_metadata $header $new_header 'keywords' $env:keywords
  $new_header = set_metadata $header $new_header 'manager' $env:manager
  sc $file (gc $file | Out-String).replace($header, ($new_header -replace "{|}", "")) -NoNewline

  if((gc $file | Out-String) -match "#*\s*RELATED\s*LINKS\s*(.|\n)*")
  {
    $related_links = $matches[0]
    $new_related_links = $matches[0]
    $related_links | sls "\[\S.*\]\(.*\)" -AllMatches | % matches | ? {$_ -match ".md\s*\)" -and $_ -notmatch "xref:"} | % {
      $value = "(xref:" + $file_rel_path.Substring(1, $file_rel_path.LastIndexOf('/'))
      $new_related_links = $new_related_links.replace($_, ($_ -replace "\([^a-z]*", $value -replace "/*$root_name/*",""))
    }
    sc $file (gc $file | Out-String).replace($related_links, $new_related_links) -NoNewline
  }
}
function get_toc
{
  if(Test-Path $toc_path)
  {
    rm $toc_path
  }
  ni $toc_path
  ls $global:root_path -dir | % {do_get_toc $_.FullName 0} 
  sc $toc_path (gc $toc_path | Out-String).replace("\", "/") -NoNewline
}
function global:do_get_toc($folder_path, $level)
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
  
  $sub_folders = ls $folder_path -dir
  if($sub_folders -eq $null)
  {
    $files = (ls $folder_path) | ? { $_.Extension -eq '.md' } | select -ExpandProperty FullName
    $landing_page = ""
    $files | ? {(gc $_ | Out-String) -match $pattern -and $matches[1] -match 'Module\s*Name\s*:'} | select -First 1 | % {
      ac $toc_path ($pre + "  href: " + ($_ -replace ".*$global:root_name", ".."))
      $landing_page = $_
    }

    ac $toc_path ($pre + "  items:")
    $pre = $pre + "    "
    $files | ? {$_ -ne $landing_page} | % {
      ac $toc_path ($pre + "- name: " + (gi $_).BaseName + "`r`n" + $pre + "  href: " + ($_ -replace ".*$global:root_name", ".."))
    }
  }
  else
  {
    ac $toc_path ($pre + "  items:")
    if(($sub_folders | select -First 1).Name -match 'v\d(.\d)*')
    {
      $sub_folders = $sub_folders | sort -Property Name -Descending
    }
    $sub_folders | % {do_get_toc $_.FullName ($level + 1)}
  }
}

$MaxThreads = 8
$RunspacePool = [RunspaceFactory ]::CreateRunspacePool(1, $MaxThreads)
$RunspacePool.Open()
$Jobs = @()
$files = ls $global:root_path -r | ? {$_.extension -eq '.md' -and (gc $_.FullName | Out-String) -match $pattern} | % { $_.FullName }
$files | % {
  $Job = [powershell]::Create().AddScript($script_block).AddArgument($_).AddArgument($global:root_name).AddArgument($pattern)
  $Job.RunspacePool = $RunspacePool
  $Jobs += New-Object PSObject -Property @{
    RunNum = $_
    Pipe = $Job
    Result = $Job.BeginInvoke()
  }
}
Write-Host "Processing files..."
Do
{
  sleep -Seconds 1
} While ($Jobs.Result.IsCompleted -contains $false)
Write-Host "Process files completed!"

Write-Host "constructing toc..."
get_toc
Write-Host "constructing toc completed."