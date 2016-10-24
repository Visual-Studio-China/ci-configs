param(
    [string]$root_path,
    [string]$root_name,
    [string]$repo_name,
    [string]$branch,
    [string]$author,
    [string]$manager,
    [string]$service,
    [string]$prod,
    [string]$keywords,
    [string]$technology
)

$files = ls $root_path -Recurse | ? {$_.extension -eq '.md'} | % { $_.FullName }

$script_block =
{
  param($file)
  $pattern = '^(?s)\s*[-]{3}(.*?)[-]{3}\r?\n'
  
  function set_metadata ($header, $new_header, $key, $value, $overwrite=$false)
  {
    if($header -match "$key[\s\S].*" -and $overwrite)
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
  # set or update metadata
  $date = (Get-Date (git log --pretty=format:%cd -n 1 --date=iso $file)).ToUniversalTime()
  $new_header = set_metadata $header $new_header 'updated_at' (Get-Date $date -format g) $true
  $new_header = set_metadata $header $new_header 'ms.date' (Get-Date $date -format d) $true
  
  cd $root_path
  $file_rel_path = gi $file | rvpa -Relative
  $git_prefix = 'https://github.com/' + $repo_name + '/blob/'
  $content_git_url = (New-Object System.Uri ($git_prefix + $branch + '/' + $file_rel_path)).AbsoluteUri
  $new_header = set_metadata $header $new_header 'content_git_url' $content_git_url  $true

  $git_commit_url = (New-Object System.Uri ($git_prefix + (git rev-list -1 HEAD $file) + '/' + $file_rel_path)).AbsoluteUri
  $new_header = set_metadata $header $new_header 'gitcommit' $git_commit_url  $true

  $topic_type = 'reference'
  if($header -match 'Module Name')
  {
    $topic_type = 'conceptual'
  }
  
  $new_header = set_metadata $header $new_header 'ms.topic' $topic_type $true
  $new_header = set_metadata $header $new_header 'ms.prod' $prod
  $new_header = set_metadata $header $new_header 'ms.service' $service
  $new_header = set_metadata $header $new_header 'ms.technology' $technology
  $new_header = set_metadata $header $new_header 'author' $author
  $new_header = set_metadata $header $new_header 'keywords' $keywords
  $new_header = set_metadata $header $new_header 'manager' $manager
  $new_header = $new_header.replace('{{', '').replace('}}', '')

  sc $file (gc $file | Out-String).replace($header, $new_header) -NoNewline
}

$MaxThreads = 8
$RunspacePool = [RunspaceFactory ]::CreateRunspacePool(1, $MaxThreads)
$RunspacePool.Open()
$Jobs = @()
$files | % {
  $Job = [powershell]::Create().AddScript($script_block).AddArgument($_)
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