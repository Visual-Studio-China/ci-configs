$ErrorActionPreference = 'Stop'

# overwrite filds but not delete modules due to multiple repos input
foreach($folder in (ls $global:root_path -Directory))
{
  $folder_name = Split-Path $folder.FullName -Leaf
  $target = Join-Path $env:TEMP\Azure $env:target_folder\$folder_name
  if(Test-Path $target)
  {
    rm $target -Recurse -Force
  }
  copy $folder.FullName $target -recurse -Force
}

$toc_folder = Join-Path $env:TEMP\Azure $env:target_folder\$global:root_name
if(Test-Path $toc_folder)
{
  rm $toc_folder -Recurse -Force
}

# copy project toc
ni $toc_folder -type Directory
$toc = Join-Path $toc_folder "toc.yml"
copy (Join-Path $global:root_path "toc.yml") $toc_folder

# copy project index
$index = Join-Path $global:root_path "index.md"
if(Test-Path $index)
{
  copy $index $toc_folder
}

# add content to global toc
$global_toc = Join-Path $env:TEMP\Azure $env:target_folder\toc.yml
if(!(Test-Path $global_toc))
{
  ni $global_toc
}
if(!((gc $global_toc | Out-String) -match $global:root_name))
{
  ac $global_toc ("- name: " + $global:root_name)
  if(Test-Path $index)
  {
    ac $global_toc ("  href: " + $global:root_name + "/index.md")
  }
  ac $global_toc ("  tocHref: " + $global:root_name + "/toc.yml")
}

# update breadcrumb
$breadcrumb_path = Join-Path $env:TEMP\Azure $env:target_folder\breadcrumb.json
$breadcrumb = (gc -Raw $breadcrumb_path) | ConvertFrom-Json
$children = $breadcrumb.children
if($children -ne $null)
{
  $new_node = $true
  foreach($c in $children.children)
  {
    if($c.href -match $global:root_name)
    {
      $new_node = $false
      break
    }
  }
  if($new_node)
  {
    Write-Host 'update breadcrumb...'
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

    # powershell read json array(one object array) issue, have to insert array mark manually
    sc $breadcrumb_path ('[' + ($breadcrumb | ConvertTo-Json -Depth 5) + ']') -NoNewline
    Write-Host 'update breadcrumb completed.'
  }
}