Added is_groovy

Listen on udp port 32100 

Setup rmem_max is NOT needed anymore
"
 1) create /etc/sysctl.conf file with "net.core.rmem_max = 2097152" content
 2) edit /etc/inittab and insert this line before MiSTer starts
    ...
    --> ::sysinit:/usr/sbin/sysctl -p
        ::sysinit:/media/fat/MiSTer &
    ...
"
