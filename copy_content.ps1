param(
    [string]$root_path,
    [string]$root_name,
    [string]$target
)

# overwrite filds but not delete modules due to multiple repos input
foreach($folder in (ls $root_path -Directory))
{
  $folder_name = Split-Path $folder.FullName -Leaf
  $target = Join-Path $target $folder_name
  if(Test-Path $target)
  {
    rm $target -Recurse -Force
  }
  copy $folder.FullName $target -recurse -Force
}

$toc_folder = Join-Path $target $root_name
if(Test-Path $toc_folder)
{
  rm $toc_folder -Recurse -Force
}

# copy project toc
ni $toc_folder -type Directory
$toc = Join-Path $toc_folder 'toc.yml'
copy (Join-Path $root_path "toc.yml") $toc_folder

# copy project index
$index = Join-Path $root_path "index.md"
if(Test-Path $index)
{
  copy $index $toc_folder
}

# add content to global toc
$global_toc = $target\toc.yml
if(!(Test-Path $global_toc))
{
  ni $global_toc
}
if(!((gc $global_toc | Out-String) -match $root_name))
{
  ac $global_toc ("- name: " + $root_name)
  if(Test-Path $index)
  {
    ac $global_toc ("  href: " + $root_name + "/index.md")
  }
  ac $global_toc ("  tocHref: " + $root_name + "/toc.yml")
}