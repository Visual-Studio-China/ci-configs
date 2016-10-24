$ErrorActionPreference = 'Stop'

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
