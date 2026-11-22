#!/usr/bin/env bash
# Queue `shell` job: what this station has and what is using it (Curtis, 22 Nov 2026: an audit of "ram management
# across the four computers"). Reads only; changes nothing. Summary line: memory total/free, page or swap file, cores,
# graphics memory, free disk. The full table (top 15 programs by memory) is published as <machine>-sysinfo.txt.
# Queue it: queue.sh add kind=shell args=script=sysinfo needs=<machine> priority=9 repeat=forever every_s=21600
art="${STATION_JOB_ART:-${TMPDIR:-/tmp}}"; m="${MACHINE:-${STATION_NAME:-$(hostname)}}"; out="$art/$m-sysinfo.txt"
mkdir -p "$art" 2>/dev/null
gpu=$(nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '\r')
[ -n "$gpu" ] || gpu="none-or-not-nvidia"
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    ps1='$o=Get-CimInstance Win32_OperatingSystem; $p=Get-CimInstance Win32_PageFileUsage | Select-Object -First 1;
"ram_total_mb=" + [int]($o.TotalVisibleMemorySize/1024); "ram_free_mb=" + [int]($o.FreePhysicalMemory/1024);
"page_mb=" + [int]$p.AllocatedBaseSize; "page_used_mb=" + [int]$p.CurrentUsage; "page_peak_mb=" + [int]$p.PeakUsage;
"commit_limit_mb=" + [int]($o.TotalVirtualMemorySize/1024); "commit_free_mb=" + [int]($o.FreeVirtualMemory/1024);
"cores=" + [Environment]::ProcessorCount;
"disk_free_gb=" + ((Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object { $_.DeviceID + [int]($_.FreeSpace/1GB) }) -join ",");
"--- top programs by memory (MB)";
Get-Process | Group-Object Name | ForEach-Object { [pscustomobject]@{n=$_.Name; c=$_.Count; mb=[int](($_.Group | Measure-Object WorkingSet64 -Sum).Sum/1MB)} } |
  Sort-Object mb -Descending | Select-Object -First 15 | ForEach-Object { "{0,7} {1,3}x {2}" -f $_.mb, $_.c, $_.n }'
    powershell.exe -NoProfile -NonInteractive -Command "$ps1" 2>&1 | tr -d '\r' > "$out"
    ;;
  *)
    {
      awk '/^MemTotal/{print "ram_total_mb=" int($2/1024)} /^MemAvailable/{print "ram_free_mb=" int($2/1024)}
           /^SwapTotal/{t=$2; print "page_mb=" int($2/1024)} /^SwapFree/{print "page_used_mb=" int((t-$2)/1024)}' /proc/meminfo
      echo "cores=$(nproc)"
      echo "disk_free_gb=$(df -BG --output=target,avail / /home 2>/dev/null | awk 'NR>1{gsub("G","",$2); printf "%s%s%s", s, $1, $2; s=","}')"
      echo "--- top programs by memory (MB)"
      ps -eo rss=,comm= | awk '{m[$2]+=$1; c[$2]++} END{for(k in m) printf "%7d %3dx %s\n", m[k]/1024, c[k], k}' | sort -rn | head -15
    } > "$out" 2>&1
    ;;
esac
echo "gpu=$gpu" >> "$out"
get() { sed -n "s/^$1=//p" "$out" | head -1; }
top=$(awk '/^---/{f=1; next} f && NF{printf "%s%s:%s", s, $3, $1; s=" "; if(++n==3) exit}' "$out")
[ -n "$(get ram_total_mb)" ] || { echo "FAIL sysinfo could not read memory: $(head -2 "$out" | tr '\n' ' ' | cut -c1-160)"; exit 1; }
echo "INFO sysinfo ram=$(get ram_total_mb)MB free=$(get ram_free_mb)MB page=$(get page_mb)MB page_used=$(get page_used_mb)MB cores=$(get cores) disk_free_gb=$(get disk_free_gb) gpu=[$gpu] top3=[$top]"
