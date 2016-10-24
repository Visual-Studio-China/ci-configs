# overwrite filds but not delete modules due to multiple repos input
foreach($folder in (ls $global:root_path -Directory))
{
  $folder_name = Split-Path $folder.FullName -Leaf
  $target = Join-Path $env:TEMP\Azure $env:target_folder\$folder_name
  if(Test-Path $target)
  {
    rm $target -Recurse -Force
  }
  Copy-Item $folder.FullName $target -recurse -Force
}

$toc_folder = Join-Path $env:TEMP\Azure $env:target_folder\$global:root_name
if(Test-Path $toc_folder)
{
  rm $toc_folder -Recurse -Force
}

# copy project toc
ni $toc_folder -type Directory
$toc = Join-Path $toc_folder "toc.yml"
Copy-item (Join-Path $global:root_path "toc.yml") $toc_folder

# copy project index
$index = Join-Path $global:root_path "index.md"
if(Test-Path $index)
{
  Copy-item $index $toc_folder
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