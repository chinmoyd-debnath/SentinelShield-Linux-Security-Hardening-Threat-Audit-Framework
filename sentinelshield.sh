#!/bin/bash
# SentinelShield – Final (Security Framework + CPU Scheduling)

BACKUP_DIR="$HOME/sentinel_backup"
TMPDIR="/tmp"
POLICY_FILE="$BACKUP_DIR/sentinel_policy.ini"
LOGFILE="$BACKUP_DIR/sentinel.log"
SSH_CFG="/etc/ssh/sshd_config"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
is_root() { [ "$(id -u)" -eq 0 ]; }
ensure() { mkdir -p "$BACKUP_DIR"; touch "$LOGFILE" 2>/dev/null; }
log(){ ensure; echo "[$(date '+%F %T')] $*" >> "$LOGFILE"; }
have(){ command -v "$1" >/dev/null 2>&1; }

ensure_policy() {
  ensure
  [ -f "$POLICY_FILE" ] && return
  cat >"$POLICY_FILE"<<'EOF'
[SSH]
PermitRootLogin=no
PasswordAuthentication=no
[SCAN]
MaxWorldWritableFiles=50
MaxWorldWritableDirs=50
EOF
  log "Created policy $POLICY_FILE"
}

ini_get(){ # section key file
  awk -v S="[$1]" -v K="$2" '
    $0~"^[[:space:]]*\\[.*\\][[:space:]]*$"{in=($0==S);next}
    in && $0!~"^[[:space:]]*#" && $0!~"^[[:space:]]*$"{
      split($0,a,"="); k=a[1]; v=a[2]
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",k); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v)
      if(k==K){print v; exit}
    }
  ' "$3"
}

sshd_get(){ # key -> last value
  [ -f "$SSH_CFG" ] || { echo ""; return; }
  awk -v K="$(echo "$1"|tr A-Z a-z)" '
    $0!~"^[[:space:]]*#" && tolower($1)==K{v=$2}
    END{print v}
  ' "$SSH_CFG"
}

sshd_set(){ # key value (remove all uncommented key lines then append)
  [ -f "$SSH_CFG" ] || return 1
  local k="$1" v="$2" tmp="$TMPDIR/sshd_config.sentinel.$$"
  awk -v K="$(echo "$k"|tr A-Z a-z)" '
    { if($0~"^[[:space:]]*#"){print; next}
      if(tolower($1)==K) next
      print
    }
  ' "$SSH_CFG" >"$tmp" || return 1
  echo "$k $v" >>"$tmp"
  cp "$tmp" "$SSH_CFG" && rm -f "$tmp"
}

backup_sshd(){
  ensure
  [ -f "$SSH_CFG" ] || return 1
  local ts; ts=$(date +%F_%H-%M-%S)
  cp "$SSH_CFG" "$BACKUP_DIR/sshd_config.$ts.bak" 2>/dev/null || return 1
  echo "$BACKUP_DIR/sshd_config.$ts.bak"
}

sshd_validate(){ have sshd && sshd -t 2>/dev/null; }
ssh_restart(){ systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; }

# ---------------- Original features (kept) ----------------

run_basic_scan() {
  local T="$TMPDIR/sentinel_scan.txt"

  {
    echo "=== SentinelShield: Basic Security Scan ==="
    echo

    echo "[+] World-writable files (top 10, REAL FS only):"
    # Exclude pseudo/runtime filesystems to avoid garbage results
    find / \
      \( -path /proc -o -path /sys -o -path /run -o -path /dev \) -prune -o \
      -type f -perm -0002 -printf "%m %u:%g %p\n" 2>/dev/null | head -n 10

    echo
    echo "[+] World-writable directories (top 10, includes perms + sticky bit):"
    find / \
      \( -path /proc -o -path /sys \) -prune -o \
      -type d -perm -0002 -printf "%m %u:%g %p\n" 2>/dev/null | head -n 10

    echo
    echo "[+] Quick sticky-bit check (common risky dirs):"
    for d in /tmp /var/tmp /dev/shm /run/screen /run/lock /var/lib/php/sessions; do
      [ -e "$d" ] && stat -c "%A %a %U:%G %n" "$d"
    done

    echo
    echo "[+] SSH service status:"
    systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo "ssh/sshd service not found"
  } >"$T"

  log "Basic scan"
  whiptail --title "Basic Security Scan" --scrolltext --textbox "$T" 24 90
}

check_policies() {
  ensure_policy
  local T="$TMPDIR/sentinel_policy.txt"
  local w_prl w_pa c_prl c_pa
  w_prl=$(ini_get SSH PermitRootLogin "$POLICY_FILE"); [ -z "$w_prl" ] && w_prl=no
  w_pa=$(ini_get SSH PasswordAuthentication "$POLICY_FILE"); [ -z "$w_pa" ] && w_pa=no
  c_prl=$(sshd_get PermitRootLogin); [ -z "$c_prl" ] && c_prl="(not set)"

  c_pa=$(sshd_get PasswordAuthentication); [ -z "$c_pa" ] && c_pa="(not set)"
  {
    echo "=== SentinelShield: Policy Check (INI) ==="
    echo "Policy: $POLICY_FILE"
    echo
    echo "[+] PermitRootLogin"
    echo "    Current: $c_prl"
    echo "    Policy : $w_prl"
    [ "$(echo "$c_prl"|tr A-Z a-z)" = "$(echo "$w_prl"|tr A-Z a-z)" ] && echo "    => PASS" || echo "    => FAIL"
    echo
    echo "[+] PasswordAuthentication"
    echo "    Current: $c_pa"
    echo "    Policy : $w_pa"
    [ "$(echo "$c_pa"|tr A-Z a-z)" = "$(echo "$w_pa"|tr A-Z a-z)" ] && echo "    => PASS" || echo "    => FAIL"
  } >"$T"
  log "Policy validation"
  whiptail --title "Policy Validation" --textbox "$T" 22 78
}

backup_configs() {
  local b; b=$(backup_sshd 2>/dev/null)
  if [ -n "$b" ]; then log "Backup $b"; whiptail --title "Backup" --msgbox "Backup created:\n$b" 10 70
  else whiptail --title "Backup" --msgbox "sshd_config not found.\nNothing to backup." 10 60; fi
}

cpu_scheduling_demo() {
  local T1="$TMPDIR/sentinel_cpu_before.txt" T2="$TMPDIR/sentinel_cpu_after.txt"
  ps -eo pid,pcpu,ni,comm --sort=-pcpu | head -n 10 >"$T1"
  whiptail --title "CPU Scheduling Demo (renice) - Before" --textbox "$T1" 22 78
  local PID; PID=$(whiptail --inputbox "Enter PID to LOWER its priority (increase nice):" 10 60 3>&1 1>&2 2>&3)
  [ -z "$PID" ] && return
  {
    echo "=== CPU Scheduling Demo (renice) ==="
    echo
    echo "[+] Changing priority for PID: $PID"
    echo "renice +5 $PID"
    echo
    renice +5 "$PID"
    echo
    echo "[+] After:"
    ps -p "$PID" -o pid,pcpu,ni,comm
  } >"$T2" 2>&1
  log "renice demo PID=$PID"
  whiptail --title "CPU Scheduling Demo (renice) - After" --textbox "$T2" 22 78
}

# ---------------- Report-claims features ----------------

scan_ports() {
  local T="$TMPDIR/sentinel_ports.txt"
  {
    echo "=== Open / Listening Ports ==="; echo
    if have ss; then ss -tulpen 2>/dev/null | head -n 40
    elif have netstat; then netstat -tulpen 2>/dev/null | head -n 40
    else echo "No ss/netstat found. Install iproute2 or net-tools."; fi
  } >"$T"
  log "Ports scan"
  whiptail --title "Open Ports Scan" --textbox "$T" 24 88
}

scan_suid() {
  local T="$TMPDIR/sentinel_suid.txt"
  {
    echo "=== SUID/SGID Binaries (top 30) ==="; echo
    find / -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | head -n 30
  } >"$T"
  log "SUID/SGID scan"
  whiptail --title "SUID/SGID Scan" --textbox "$T" 24 88
}

list_services() {
  local T="$TMPDIR/sentinel_services.txt"
  {
    echo "=== Services Overview ==="; echo
    echo "[+] Running services (top 40):"
    systemctl list-units --type=service --state=running 2>/dev/null | head -n 40
    echo; echo "[+] Enabled services (top 40):"
    systemctl list-unit-files --type=service --state=enabled 2>/dev/null | head -n 40
  } >"$T"
  log "Services list"
  whiptail --title "Services" --textbox "$T" 24 88
}

apply_hardening() {
  ensure_policy
  is_root || { whiptail --title "Hardening" --msgbox "Run as root (sudo) to apply hardening." 10 60; return; }
  [ -f "$SSH_CFG" ] || { whiptail --title "Hardening" --msgbox "sshd_config not found at $SSH_CFG" 10 70; return; }

  local w_prl w_pa bak
  w_prl=$(ini_get SSH PermitRootLogin "$POLICY_FILE"); [ -z "$w_prl" ] && w_prl=no
  w_pa=$(ini_get SSH PasswordAuthentication "$POLICY_FILE"); [ -z "$w_pa" ] && w_pa=no

  bak=$(backup_sshd) || { whiptail --title "Hardening" --msgbox "Backup failed. Aborting." 10 60; return; }

  sshd_set PermitRootLogin "$w_prl" || { whiptail --msgbox "Failed to set PermitRootLogin" 10 50; return; }
  sshd_set PasswordAuthentication "$w_pa" || { whiptail --msgbox "Failed to set PasswordAuthentication" 10 50; return; }

  if sshd_validate; then
    if ssh_restart; then
      log "Hardening applied. Backup=$bak"
      whiptail --title "Hardening" --msgbox "Hardening applied.\nBackup:\n$bak" 12 70
    else
      cp "$bak" "$SSH_CFG" 2>/dev/null; ssh_restart 2>/dev/null
      log "Hardening restart failed; rolled back. Backup=$bak"
      whiptail --title "Hardening" --msgbox "SSH restart failed. Rolled back:\n$bak" 12 70
    fi
  else
    cp "$bak" "$SSH_CFG" 2>/dev/null
    log "Hardening invalid config; rolled back. Backup=$bak"
    whiptail --title "Hardening" --msgbox "Validation failed. Rolled back:\n$bak" 12 70
  fi
}

rollback() {
  ensure
  is_root || { whiptail --title "Rollback" --msgbox "Run as root (sudo) to rollback." 10 60; return; }
  local b; b=$(ls -1 "$BACKUP_DIR"/sshd_config.*.bak 2>/dev/null | sort -r | head -n 12)
  [ -z "$b" ] && { whiptail --title "Rollback" --msgbox "No backups found in:\n$BACKUP_DIR" 10 70; return; }

  local items=() i=1 f
  while IFS= read -r f; do items+=("$i" "$(basename "$f")"); i=$((i+1)); done <<<"$b"
  local c; c=$(whiptail --title "Rollback" --menu "Select backup to restore:" 20 78 12 "${items[@]}" 3>&1 1>&2 2>&3) || return
  local sel; sel=$(echo "$b" | sed -n "${c}p")
  [ -z "$sel" ] && return

  cp "$sel" "$SSH_CFG" 2>/dev/null || { whiptail --msgbox "Restore failed." 10 40; return; }
  if sshd_validate; then ssh_restart 2>/dev/null; fi
  log "Rollback restored $sel"
  whiptail --title "Rollback" --msgbox "Restored:\n$sel" 12 70
}

report() {
  ensure_policy; ensure
  local ts rep score=100
  ts=$(date +%F_%H-%M-%S)
  rep="$BACKUP_DIR/security_report_$ts.txt"

  local wwf wwd maxf maxd
  wwf=$(find / -type f -perm -0002 2>/dev/null | wc -l | tr -d ' ')
  wwd=$(find / -type d -perm -0002 2>/dev/null | wc -l | tr -d ' ')
  maxf=$(ini_get SCAN MaxWorldWritableFiles "$POLICY_FILE"); [ -z "$maxf" ] && maxf=50
  maxd=$(ini_get SCAN MaxWorldWritableDirs "$POLICY_FILE"); [ -z "$maxd" ] && maxd=50
  [ "$wwf" -gt "$maxf" ] && score=$((score-15))
  [ "$wwd" -gt "$maxd" ] && score=$((score-15))

  local w_prl w_pa c_prl c_pa
  w_prl=$(ini_get SSH PermitRootLogin "$POLICY_FILE"); [ -z "$w_prl" ] && w_prl=no
  w_pa=$(ini_get SSH PasswordAuthentication "$POLICY_FILE"); [ -z "$w_pa" ] && w_pa=no
  c_prl=$(sshd_get PermitRootLogin); [ -z "$c_prl" ] && c_prl="(not set)"
  c_pa=$(sshd_get PasswordAuthentication); [ -z "$c_pa" ] && c_pa="(not set)"
  [ "$(echo "$c_prl"|tr A-Z a-z)" != "$(echo "$w_prl"|tr A-Z a-z)" ] && score=$((score-20))
  [ "$(echo "$c_pa"|tr A-Z a-z)" != "$(echo "$w_pa"|tr A-Z a-z)" ] && score=$((score-20))
  [ "$score" -lt 0 ] && score=0

  {
    echo "=== SentinelShield Security Report ==="
    echo "Generated: $(date)"
    echo "Host: $(hostname)"
    echo "Policy: $POLICY_FILE"
    echo "Log: $LOGFILE"
    echo
    echo "[1] Permissions"
    echo "World-writable files: $wwf (max $maxf)"
    echo "World-writable dirs : $wwd (max $maxd)"
    echo "Top 10 files:"; find / -type f -perm -0002 2>/dev/null | head -n 10
    echo; echo "Top 10 dirs:"; find / -type d -perm -0002 2>/dev/null | head -n 10
    echo
    echo "[2] SSH Policy"
    echo "PermitRootLogin: Current=$c_prl | Policy=$w_prl"
    echo "PasswordAuthentication: Current=$c_pa | Policy=$w_pa"
    echo "SSH status:"; systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo "ssh/sshd not found"
    echo
    echo "[3] Ports (top 40)"
    if have ss; then ss -tulpen 2>/dev/null | head -n 40
    elif have netstat; then netstat -tulpen 2>/dev/null | head -n 40
    else echo "No ss/netstat."; fi
    echo
    echo "[4] SUID/SGID (top 30)"
    find / -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | head -n 30
    echo
    echo "[5] Services (top 20 each)"
    echo "Running:"; systemctl list-units --type=service --state=running 2>/dev/null | head -n 20
    echo; echo "Enabled:"; systemctl list-unit-files --type=service --state=enabled 2>/dev/null | head -n 20
    echo
    echo "=== Score: $score / 100 ==="
  } >"$rep"

  log "Report $rep score=$score"
  whiptail --title "Report Generated" --msgbox "Saved:\n$rep\n\nLog:\n$LOGFILE" 14 80
}

# ---------------- CPU Scheduling (FCFS/SJF/RR) ----------------

PIDS=(); ARR=(); BUR=()
sched_get() {
  local N; N=$(whiptail --inputbox "Processes count (1..12):" 10 60 "4" 3>&1 1>&2 2>&3) || return 1
  [[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -ge 1 ] && [ "$N" -le 12 ] || { whiptail --msgbox "Invalid N" 10 40; return 1; }
  PIDS=(); ARR=(); BUR=()
  local i a b
  for ((i=1;i<=N;i++)); do
    a=$(whiptail --inputbox "Arrival time for P$i (>=0):" 10 60 "0" 3>&1 1>&2 2>&3) || return 1
    b=$(whiptail --inputbox "Burst time for P$i (>=1):" 10 60 "5" 3>&1 1>&2 2>&3) || return 1
    [[ "$a" =~ ^[0-9]+$ ]] && [[ "$b" =~ ^[0-9]+$ ]] && [ "$b" -ge 1 ] || { whiptail --msgbox "Bad input" 10 40; return 1; }
    PIDS+=("P$i"); ARR+=("$a"); BUR+=("$b")
  done
}

sort_arrival() {
  local n=${#PIDS[@]}; IDX=(); local i j
  for ((i=0;i<n;i++)); do IDX+=("$i"); done
  for ((i=0;i<n;i++)); do for ((j=0;j<n-1;j++)); do
    [ "${ARR[${IDX[j]}]}" -gt "${ARR[${IDX[j+1]}]}" ] && { t=${IDX[j]}; IDX[j]=${IDX[j+1]}; IDX[j+1]=$t; }
  done; done
}

sched_out() {
  local title="$1" T="$TMPDIR/sched_result.txt"
  : >"$T"
  echo "=== CPU Scheduling: $title ===" >>"$T"
  echo >>"$T"; echo "Gantt:" >>"$T"; echo "$GANTT" >>"$T"; echo >>"$T"
  printf "%-6s %-5s %-5s %-5s %-5s\n" PID AT BT WT TAT >>"$T"
  echo "--------------------------------" >>"$T"
  local n=${#PIDS[@]} sumw=0 sumt=0 i
  for ((i=0;i<n;i++)); do
    printf "%-6s %-5s %-5s %-5s %-5s\n" "${PIDS[i]}" "${ARR[i]}" "${BUR[i]}" "${WT[i]}" "${TAT[i]}" >>"$T"
    sumw=$((sumw+WT[i])); sumt=$((sumt+TAT[i]))
  done
  echo >>"$T"
  echo "Avg WT  = $(awk "BEGIN{printf \"%.2f\", $sumw/$n}")" >>"$T"
  echo "Avg TAT = $(awk "BEGIN{printf \"%.2f\", $sumt/$n}")" >>"$T"
  log "Scheduling $title"
  whiptail --title "Scheduling Result" --textbox "$T" 24 78
}

fcfs() {
  local n=${#PIDS[@]} i t=0; WT=(); TAT=(); for ((i=0;i<n;i++)); do WT[i]=0; TAT[i]=0; done
  sort_arrival; GANTT="(time)"
  for idx in "${IDX[@]}"; do
    [ "$t" -lt "${ARR[idx]}" ] && t=${ARR[idx]}
    WT[idx]=$((t-ARR[idx])); t=$((t+BUR[idx])); TAT[idx]=$((t-ARR[idx]))
    GANTT="$GANTT | ${PIDS[idx]} ($t)"
  done
  sched_out "FCFS"
}

sjf_np() {
  local n=${#PIDS[@]} i; WT=(); TAT=(); DONE=()
  for ((i=0;i<n;i++)); do WT[i]=0; TAT[i]=0; DONE[i]=0; done
  sort_arrival; local t=${ARR[${IDX[0]}]} done=0; GANTT="(time)"
  while [ "$done" -lt "$n" ]; do
    local pick=-1 best=999999
    for ((i=0;i<n;i++)); do
      [ "${DONE[i]}" -eq 0 ] && [ "${ARR[i]}" -le "$t" ] && [ "${BUR[i]}" -lt "$best" ] && { pick=$i; best=${BUR[i]}; }
    done
    if [ "$pick" -eq -1 ]; then
      local next=999999
      for ((i=0;i<n;i++)); do [ "${DONE[i]}" -eq 0 ] && [ "${ARR[i]}" -lt "$next" ] && next=${ARR[i]}; done
      t=$next; continue
    fi
    WT[pick]=$((t-ARR[pick])); t=$((t+BUR[pick])); TAT[pick]=$((t-ARR[pick]))
    DONE[pick]=1; done=$((done+1)); GANTT="$GANTT | ${PIDS[pick]} ($t)"
  done
  sched_out "SJF (Non-preemptive)"
}

rr() {
  local q; q=$(whiptail --inputbox "Round Robin quantum (>=1):" 10 60 "2" 3>&1 1>&2 2>&3) || return
  [[ "$q" =~ ^[0-9]+$ ]] && [ "$q" -ge 1 ] || { whiptail --msgbox "Invalid quantum" 10 40; return; }
  local n=${#PIDS[@]} i; WT=(); TAT=(); REM=(); FIN=(); ENQ=()
  for ((i=0;i<n;i++)); do WT[i]=0; TAT[i]=0; REM[i]=${BUR[i]}; FIN[i]=0; ENQ[i]=0; done
  sort_arrival; local t=${ARR[${IDX[0]}]} queue=() head=0 done=0; GANTT="(time)"
  for ((i=0;i<n;i++)); do [ "${ARR[i]}" -le "$t" ] && [ "${ENQ[i]}" -eq 0 ] && { queue+=("$i"); ENQ[i]=1; }; done
  while [ "$done" -lt "$n" ]; do
    if [ "$head" -ge "${#queue[@]}" ]; then
      local next=999999
      for ((i=0;i<n;i++)); do [ "${FIN[i]}" -eq 0 ] && [ "${ENQ[i]}" -eq 0 ] && [ "${ARR[i]}" -lt "$next" ] && next=${ARR[i]}; done
      t=$next
      for ((i=0;i<n;i++)); do [ "${FIN[i]}" -eq 0 ] && [ "${ENQ[i]}" -eq 0 ] && [ "${ARR[i]}" -le "$t" ] && { queue+=("$i"); ENQ[i]=1; }; done
      head=0; continue
    fi
    local p=${queue[head]}; head=$((head+1))
    local run=$q; [ "${REM[p]}" -lt "$run" ] && run=${REM[p]}
    t=$((t+run)); REM[p]=$((REM[p]-run)); GANTT="$GANTT | ${PIDS[p]} (+$run=>$t)"
    for ((i=0;i<n;i++)); do [ "${FIN[i]}" -eq 0 ] && [ "${ENQ[i]}" -eq 0 ] && [ "${ARR[i]}" -le "$t" ] && { queue+=("$i"); ENQ[i]=1; }; done
    if [ "${REM[p]}" -eq 0 ]; then FIN[p]=1; done=$((done+1)); TAT[p]=$((t-ARR[p])); else queue+=("$p"); fi
    [ "$head" -gt 25 ] && { queue=("${queue[@]:head}"); head=0; }
  done
  for ((i=0;i<n;i++)); do WT[i]=$((TAT[i]-BUR[i])); done
  sched_out "Round Robin (q=$q)"
}

sched_menu() {
  sched_get || return
  while true; do
    local c
    c=$(whiptail --title "CPU Scheduling Algorithms" --menu "Select algorithm:" 18 70 10 \
      "1" "FCFS" "2" "SJF (Non-preemptive)" "3" "Round Robin" "4" "Back" 3>&1 1>&2 2>&3) || return
    case "$c" in 1) fcfs ;; 2) sjf_np ;; 3) rr ;; 4) return ;; esac
  done
}

# ---------------- Main menu ----------------

main_menu() {
  need whiptail; ensure_policy; ensure
  while true; do
    local c
    c=$(whiptail --title "SentinelShield UI" --menu "Select an option:" 22 78 12 \
      "1" "Run Basic Security Scan" \
      "2" "Validate Security Policies (INI)" \
      "3" "Open Ports Scan (ss/netstat)" \
      "4" "SUID/SGID Scan" \
      "5" "Enabled & Running Services" \
      "6" "Apply SSH Hardening (Policy + Backup)" \
      "7" "Rollback SSH Config from Backup" \
      "8" "Generate Security Report + Score + Log" \
      "9" "CPU Scheduling Algorithms (FCFS/SJF/RR)" \
      "10" "CPU Scheduling Demo (renice)" \
      "11" "Backup Config Files (manual)" \
      "12" "Exit" 3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && clear && exit 0
    case "$c" in
      1) run_basic_scan ;;
      2) check_policies ;;
      3) scan_ports ;;
      4) scan_suid ;;
      5) list_services ;;
      6) apply_hardening ;;
      7) rollback ;;
      8) report ;;
      9) sched_menu ;;
      10) cpu_scheduling_demo ;;
      11) backup_configs ;;
      12) clear; exit 0 ;;
    esac
  done
}

main_menu
