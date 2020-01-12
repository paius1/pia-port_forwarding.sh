#!/usr/bin/env bash
#
#  Get port forwarding assignment from Private Internet Access VPN
#    using api code from the PIA website
#
#  this must be run within two minutes of connecting to the VPN
#   port will be written to ${pFLOG}
#   
#  This script can also
#   start the transmission-daemon with the forwarded port
#   and mount any network shares $pFLOG
#
#  uses curl, geoiplookup, sshfs, and systemd
#
#  to run this without a password
#   sudo visudo -f /etc/sudoers.d/your_username
#      and add the following lines 
#   YOUR_USERNAME ALL= NOPASSWD: /bin/systemctl start transmission-daemon.service
#   YOUR_USERNAME ALL= NOPASSWD: /bin/systemctl stop transmission-daemon.service
#   YOUR_USERNAME ALL= NOPASSWD: /bin/systemctl start openvpn.service
#   YOUR_USERNAME ALL= NOPASSWD: /bin/systemctl stop openvpn.service
#
#   to run this at boot use: 
#    crontab -e 
#      and add the following lines
#   BOOTING=1
#   @reboot /path/to/pia-port-forwarding.sh
#
###
#    Copyright (c) 2020, Paul L. Groves
#    All rights reserved.
#####

  # log output
    pFLOG=/tmp/pia-port-forwarding.log

  # local gateway/router
    gATEWAY='192.168.X.X'

  # service name for openvpn
    oPENVPN='openvpn@client.service'

  # current PIA servers with port forwarding
  # Canada France Germany Spain Switzerland Czech Republic Sweden Romania Israel
  # Montreal shows up as États Unis go figure
    pIA_LOCATIONS=( 'CA' 'FR' 'DE' 'ES' 'CH' 'CZ' 'SE' 'RO' 'IL' )

  # wait for connections
    tIMEOUT='10'

  # change transmission-daemon settings
    tRANSMISSION='yes' # yes/no or empty
      sETTINGS="${HOME}/.config/transmission-daemon/settings.json"

  # check network shares are mounted
    nETWORK_SHARES='yes' # yes/no or empty
      cREATE_DIRECTORIES='no'
    # Add shares here
    # ['share#']="user       host    /remote/share        /mount/point"
      #declare -A sHARES=(
      #['share1']="user      host    /remote/share        /mount/point"
      #)

  # colors for output    
    BLU="\\e[01;34m"; RED="\\e[01;31m"; NRM="\\e[00m"; GRN="\\e[01;32m"
    YLW="\\e[01;33m"; Blink="\\e[5m"; BLD="\\e[01m"; DIM="\\e[2m"

  function _help() {
    echo -e >&2 "\\n    ${BASH_SOURCE##*/}"
    sed >&2 -n "1d; /^###/q; /^#/!q; s/^#*//; s/^ //; \
        s/SCRIPTNAME/${BASH_SOURCE##*/}/; p" \
        "${BASH_SOURCE%/*}/${BASH_SOURCE##*/}"
  return 0
}
[ "${#}" -eq 1 ] && { _help; exit 1; }

# log output call with:  _output_log "message" "${pFLOG}"
  function _output_log() {
               local message="${1}" log="${2}"; [[ -z "${log}" ]] && log=/dev/null
               echo -e "$(date "+%x %X")  ${message}" | tee -a "${log}"
  return 0
}

# Function to exit cleanly
  mE=$0; pIDOFME=$$
  function _die() {
               local status="${1}" message="${2}"
               [[ -z "${status}" ]] && 
                   { _output_log "${RED}SIGINT caught...${NRM}" "${log}" && exit 1; }
               case "${status}" in
                   0) color="${GRN}" ;;
                   1) color="${YLW}" ;;
                   *) _output_log \
                      "${message}" \
                      "${pFLOG}"
                      sudo /bin/systemctl stop "${oPENVPN}" && sudo /bin/systemctl start "${oPENVPN}"
                      exec "${mE}" &
                      kill "${pIDOFME}"
                     ;;
               esac
               _output_log "${color}exit ${status} ${message}${NRM}" "${pFLOG}"
               exit "${status}"
  return 0
}

# Check network connection
  function _connection_check() {
               local host="${1}" log="${2}" timeout="${3}" attempts='0'
               _output_log "${BLU}${DIM}Checking for Network connection to ${host}...${NRM}" "${log}"
               until ping -c 1 -W 1 "${host}" > /dev/null 2>&1; do
                   ((attempts++))
                   [[ "${attempts}" -eq "${timeout}" ]] && { _output_log "${RED}Not connected to ${host}${NRM}" "${log}"; return 1; }
                   sleep 1
               done
               _output_log "${GRN}${DIM}Connected to ${host}${NRM}" "${log}"
  return 0
}

# Connect to PIA API
  function _port_forward_request() {
               curl "http://209.222.18.222:2000/?client_id=$(head -n 100 /dev/urandom | sha256sum | tr -d " -")" 2>/dev/null
  return 0
}

# for network shares set $nETWORK_SHARES=yes and define sHARES array
  function _mount_sshfs() {
               local user="${1}" host="${2}" share="${3}" 
               local mnt="${4}" log="${5}" timeout="${6}"
               local options='reconnect,ServerAliveInterval=15,ServerAliveCountMax=3'

               # Check if already mounted  
                 mntpoint="$(grep "${user}@${host}:${share}" /etc/mtab | cut -d' ' -f2)"
                 [[ "${mntpoint}" ]] &&
                    { _output_log "${YLW}${share} mounted on ${mntpoint}${NRM}" "${log}"; return 0; }

               # Check for connections to host  
                 _connection_check "${host}" "${log}" "${timeout}"  || return 1

               # Check if mount point exists
                 if [ ! -d "${mnt}" ]; then
                     _output_log "${YLW}${mnt} does not exist${NRM}" "${log}"
               # cREATE_DIRECTORIES=yes try to create 
                     if [[ "${cREATE_DIRECTORIES}" && "${cREATE_DIRECTORIES}" != "no" ]]; then
                        mkdir "${mnt}" 2>/dev/null || 
                              { _output_log "${RED}Can't create ${mnt}${NRM}" "${log}"; return 1; }
                        _output_log "${YLW} Created ${mnt}${NRM}" "${log}"
                     else
                        _output_log "${YLW} Not creating ${mnt}${NRM}" "${log}"
                        return 1
                     fi
                 fi

               # mount network share
                 if ! rETURN="$(sshfs -o "${options}" "${user}"@"${host}":"${share}" "${mnt}")"; then 
                    _output_log "${RED}Failed to mount ${share} on ${mnt}...${NRM}" "${log}"
                    _output_log "${YLW}${rETURN}${NRM}" "${log}"
                    return 1
                 else
                    _output_log "${GRN}${share} mounted on ${mnt}${NRM}" "${log}"
                 fi
  return 0
}

  trap _die INT
     echo -e >&2 "\\nCtrl-C to exit\\n"

# if running from crontab or rc.local set users ENVIRONMENT
  if [[ "$BOOTING" ]]; then
     _output_log "${BLU}${DIM}Called at boot${NRM}" "${pFLOG}"
     export PATH="${HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
     sleep "$((tIMEOUT/2))"
  fi

# Check for required external programs in PATH
  command -v curl >/dev/null 2>&1 || _die 1 "curl not found in path"
  command -v geoiplookup >/dev/null 2>&1 || _die 1 "geoiplookup not found in path"
  command -v sshfs >/dev/null 2>&1 || _die 1 "sshfs not found in path"

# Wait for Network connection
  _connection_check "${gATEWAY}" "${pFLOG}" "${tIMEOUT}" || _die 1 "No Network Connection"

# Wait for VPN connection
  _output_log "${BLU}${DIM}Checking for  VPN connection to one of ${pIA_LOCATIONS[*]}...${NRM}" "${pFLOG}"
  until [[ "${pIA_LOCATIONS[*]}" =~ $(curl -A curl -s ipinfo.io/country) ]]; do
        _output_log "${YLW}not connected to PIA yet...${NRM}" "${pFLOG}"
        sleep 3
        ((timer++)); [[ "${timer}" -ge "${tIMEOUT}" ]] && 
                        { _die 2 \
                          "${Blink}${RED}${BLD}PIA CONNECTION FAILED... Restarting ${oPENVPN}${NRM}"; }
  done
  _output_log "${GRN}Connected to PIA VPN in $( curl -s -4 ifconfig.co | \
              xargs geoiplookup | cut -d',' -f2)${NRM}" "${pFLOG}"

# get port forwarding assignment
  _output_log "${BLU}${DIM}Requesting port forward assignment from PIA...${NRM}" "${pFLOG}"
  jSON="$(_port_forward_request)"

# Act on received data
  if [[ -z "${jSON}" ]]; then
     _die 2 "${Blink}${RED}${BLD}Connection reset by peer... RESTARTING ${oPENVPN}${NRM}"
  fi                           

# Check for valid port number and start transmission-daemon
  pORT=$(echo "$jSON" |cut -d: -f2| tr -d '}')
  if [[ "${pORT}" =~ ^[+-]?[0-9]*$ ]]; then
     _output_log "${GRN}Forwarding port is ${pORT}${NRM}" "${pFLOG}"
     [[ ! "${tRANSMISSION}" || "${tRANSMISSION}" = "no" ]] && _die 0

     # Stop transmission-daemon to change settings.json move this when working
       if [ "$(pgrep transmission)" ]; then
           _output_log "${Blink}${YLW}${BLD}STOPPING TRANSMISSION-DAEMON${NRM}" "${pFLOG}"
           sudo /bin/systemctl stop transmission-daemon.service 2>/dev/null || _die 1 "Couldn't stop transmission-daemon"
       fi

     # Set up tranmission daemon
       _output_log "${BLU}${DIM}Setting up transmission-daemon environment...${NRM}" "${pFLOG}"

     # backup tranmsission settings
       cp "${sETTINGS}" "${sETTINGS}".bak || 
          { _output_log "${Blink}${RED}Can't backup settings${NRM}" "${pFLOG}"; _die 1; }

     # change port number in settings.json
       sed  -i -e 's%\(.*"peer-port": \).*\(,\)%\1'"${pORT}"'\2%' "${sETTINGS}" ||
          { _output_log "${Blink}${RED}Can't edit ${sETTINGS}${NRM}" "${pFLOG}"; _die 1; }

     # Mount for Network Shares?
       if [[ "${nETWORK_SHARES}" ]]; then
          _output_log "${BLU}${DIM}Adding network shares...${NRM}" "${pFLOG}"
          for key in "${!sHARES[@]}"; do 
              read -r -a variables <<< "${sHARES[$key]}"
              _mount_sshfs "${variables[0]}" "${variables[1]}" "${variables[2]}" "${variables[3]}"  "${pFLOG}" "${tIMEOUT}"
          done
          sleep  $((tIMEOUT/2))
       fi

     # Restart transmission-daemon
       _output_log "${BLU}${BLD}Starting transmission-daemon...${NRM}" "${pFLOG}"
       sudo /bin/systemctl start transmission-daemon.service 2>/dev/null
          sleep  $((tIMEOUT/2))
       if systemctl is-active --quiet transmission-daemon.service; then
        _output_log "${GRN}Transmission-daemon running${NRM}" "${pFLOG}"
     else
        _output_log "${YLW}Check status of transmission-daemon${NRM}
                    \\t/bin/systemctl status transmission-daemon.service" "${pFLOG}"
     fi
  else 
     _output_log "${Blink}${RED}${mE} failed with ${jSON}${NRM}" "${pFLOG}"
  fi
_die 0 "scripted completed"
