# pia-port_forwarding.sh
  Get port forwarding assignment from Private Internet Access VPN

    using api code from the PIA website

  this must be run within two minutes of connecting to the VPN
  
   port will be written to user defined log file
   
  This script can also
   start the transmission-daemon with the forwarded port
   and mount any network shares

  uses curl, geoiplookup, sshfs, and systemd

  to run without a password
  
   `sudo visudo -f /etc/sudoers.d/your_username`
  
  and add the following lines 
  
   `USERNAME ALL= NOPASSWD: /bin/systemctl start transmission-daemon.service`
   `USERNAME ALL= NOPASSWD: /bin/systemctl stop transmission-daemon.service`
   `USERNAME ALL= NOPASSWD: /bin/systemctl start openvpn.service`              
   `USERNAME ALL= NOPASSWD: /bin/systemctl stop openvpn.service`

  to run at boot use: 
   
    crontab -e
   
  and add the following lines
   
   `BOOTING=1`
   
   `@reboot /path/to/pia-port_forwarding.sh`



    Copyright (c) 2020, Paul L. Groves
    All rights reserved.
