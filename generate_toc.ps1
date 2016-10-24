param(
    [string]$root_path,
    [string]$root_name,
    [string]$toc_path
)

function GetToc
{
  if(Test-Path $toc_path)
  {
    rm $toc_path
  }
  ni $toc_path
  Write-Host "constructing toc..."
  
  foreach($subFolder in (ls $root_path -Directory))
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
    ac $toc_path ($pre + "  href: " + (gi $index | rvpa -Relative).replace('\' + $root_name, '.'))
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
        ac $toc_path ($pre + "  href: " + (gi $file | rvpa -Relative).replace('\' + $root_name, '.'))
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
        ac $toc_path ($pre + "  href: " + (gi $file | rvpa -Relative).replace('\' + $root_name, '.'))
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