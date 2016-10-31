# 1. copy docs to processing repo
# 2. copy toc and index if there is any
# 3. update global toc and breadcrumb if necessary

$ErrorActionPreference = 'Stop'
ls $global:root_path -dir | % {
  $target = Join-Path $env:TEMP\Azure $env:target_folder | Join-Path -ChildPath (Split-Path $_.FullName -Leaf)
  if(Test-Path $target)
  {
    rm $target -Recurse -Force
  }
  copy $_.FullName $target -Recurse -Force
}

$toc_folder = Join-Path $env:TEMP\Azure $env:target_folder\$global:root_name
if(!(Test-Path $toc_folder))
{
  ni $toc_folder -type Directory
}

copy (Join-Path $global:root_path "toc.yml") $toc_folder
$index = Join-Path $global:root_path "index.md"
if(Test-Path $index)
{
  copy $index $toc_folder
}
$global_toc = Join-Path $env:TEMP\Azure $env:target_folder\toc.yml
if(!(Test-Path $global_toc))
{
  ni $global_toc
}
if((gc $global_toc | Out-String) -notmatch $global:root_name)
{
  ac $global_toc ("- name: " + $global:root_name)
  if(Test-Path $index)
  {
    ac $global_toc ("  href: " + $global:root_name + "/index.md")
  }
  ac $global_toc ("  tocHref: " + $global:root_name + "/toc.yml")
}
$breadcrumb_path = Join-Path $env:TEMP\Azure $env:target_folder\breadcrumb.json
$breadcrumb = (gc -Raw $breadcrumb_path) | ConvertFrom-Json
$children = $breadcrumb.children
if($children -ne $null)
{
  $new_node = $true
  $children.children | ? {$_.href -match $global:root_name} | select -First 1 | % {$new_node = $false}
  if($new_node)
  {
    $new_child = New-Object PSObject -Property @{
      href = $children[0].href + $global:root_name + "/"
      homepage = $children[0].href + $global:root_name + "/"
      toc_title = $global:root_name
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

    Write-Host 'update breadcrumb...'
    # powershell read json array(one object array) issue, have to insert array mark manually
    sc $breadcrumb_path ('[' + ($breadcrumb | ConvertTo-Json -Depth 5) + ']') -NoNewline
    Write-Host 'update breadcrumb completed.'
  }
}