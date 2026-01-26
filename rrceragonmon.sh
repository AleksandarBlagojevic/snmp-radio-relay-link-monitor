#!/bin/bash

# Pomocni file-ovi za pravljenje logova 
# Trenutno vreme i datum u formatu yyyymmdd_hhmm
VREME=$(date '+%Y%m%d_%H%M')
CERLOG="cer_info_$VREME.log"
NEDOSTUPNI="nedostupni_$VREME.txt"
REZULTAT="rezultat_$VREME.txt"
#OUTPUT_FILE="topologija_$VREME.csv"
# Pravim te fajlove na pocetku
touch $CERLOG
touch $NEDOSTUPNI
touch $REZULTAT

# Funkcija koja pravi log u formatu "[datum_vreme] poruka"
make_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $CERLOG
}

# SNMP funkcija koja koristi SNMPwalk ili SNMPget zavisnosti od mode, verzije, community, ip, oida
# snmp_call("[get|walk]", 2c, community, ip, oid , '[hostname]', '[log_name]')
snmp_call() {
    local mode=$1
    local version=$2
    local community=$3
    local ip=$4
    local oid=$5
    local hostname=$6
    local text=$7
     

    local start=$(date +%s.%N)

    if [[ "$mode" == "get" ]]; then
        result=$(snmpget -v$version -c $community -m ALL -t0.1 -Ovanq $ip $oid)
    else
        result=$(snmpwalk -v$version -c $community -m ALL -t0.1 -Ona $ip $oid)
    fi

    local end=$(date +%s.%N)
    local time=$(awk -v s="$start" -v e="$end" 'BEGIN {printf "%.3f", e - s}')

    if [[ "$hostname" == "" ]]; then
        make_log "[$result] Vreme odgovora ${text}: ${time}s "
    else
        make_log "[$hostname] Vreme odgovora ${text}: ${time}s "
    fi

    echo $result
}

echo "============================== POKRENUTA SKRIPTA ==============================" >> $CERLOG


CSV_FILE="test.csv"

ip_command="awk -F'\",\"' '
/^\"?IP Address\"?,/ { start=1; next }         # citaj dok ne naidjes header
start {
    sub(/\r$/, \"\")                           # skini CR ako je CRLF
    gsub(/^\"/, \"\", \$1)                     # skini pocetni navodnik
    gsub(/\"$/, \"\", \$NF)                    # skini zavrsni navodnik
    out = \$1
    for (i=2; i<=NF; i++) out = out \"\t\" \$i # spoji sva polja TAB-om
    if (out != \"\") print out
}
' \"$CSV_FILE\""
readarray -t ip_array < <(eval "$ip_command")

make_log "Pronadjeno ${#ip_array[@]} IP adresa "


# kolone su: 0:IP Address, 1:Status, 2:Name, 3:System Name, 4:System Location,
#            5:System Contact, 6:Product Type, 7:Configuration, 8:Last Reachable
get_cell() {
  local row="$1" col="$2"
  IFS=$'\t' read -r -a cols <<< "${ip_array[row]}"   # podeli taj red po TAB-u
  printf '%s\n' "${cols[col]}"
}

# SPISAK SVIH OIDA

CERHOSTNAME=1.3.6.1.2.1.1.5.0
INTERFACES=1.3.6.1.4.1.2281.10.9.8.2.1.2
SERVICES=1.3.6.1.4.1.2281.10.8.5.2.1.8
CONFIGURATION=1.3.6.1.4.1.2281.10.1.5.8.1.3
IPADDRESS=1.3.6.1.4.1.2281.10.7.3.1.1.3


COMMUNITY=public


echo "==============================" >> "$REZULTAT"

# ================== Glavna obrada ==================
for idx in "${!ip_array[@]}"; do
    # Izvuci polja iz trenutnog reda
    ip=$(get_cell "$idx" 0)
    #status=$(get_cell "$idx" 1)

    # Trim potencijalnih space-ova
    ip="${ip##*( )}"; ip="${ip%%*( )}"

    # Preskoci prazne IP-eve nevazece
    if [[ -z "$ip" || "$ip" == "0.0.0.0" || "$ip" == -* ]]; then
        make_log "Red $idx preskocen (prazan/los IP: '$ip')"
        continue
    fi

    make_log "============================================================"
    make_log "Obrada [$ip] ..."

    # Hostname
    start_host=$(date +%s.%N)
    HOSTNAME=$(snmp_call "get" 2c "$COMMUNITY" "$ip" "$CERHOSTNAME" "" "hostname")
    # Proveravamo da li je dostupan, ako nije nastavljamo sa drugom adresom
    if [[ -z "$HOSTNAME" ]]; then
        make_log "[$ip] NEDOSTUPAN! nema Hostname odgovora (${time_host}s)"
        echo "$ip" >> $NEDOSTUPNI
        make_log "Zavrsena [$ip] "
        make_log "=============================="
        continue
    fi
    # Upisujemo u rezultat
    echo "[$ip] $HOSTNAME" >> $REZULTAT
    
    TYPE=$(get_cell "$idx" 6)
    echo $TYPE >> $REZULTAT
    INTERFACESLIST=$(snmp_call "walk" 2c $COMMUNITY $ip $INTERFACES $HOSTNAME "Physical Interfaces ifAlias")
    echo "----- Physical Interfaces ifAlias ----- " >> $REZULTAT
    echo $INTERFACESLIST >> $REZULTAT
    SERVICESLIST=$(snmp_call "walk" 2c $COMMUNITY $ip $SERVICES $HOSTNAME "Ethernet and TDM services")
    echo "----- Ethernet and TDM services ----- " >> $REZULTAT
    echo $SERVICESLIST >> $REZULTAT
    CONFIGURATIONLIST=$(snmp_call "walk" 2c $COMMUNITY $ip $CONFIGURATION $HOSTNAME "Chassis configuration")
    echo "----- Chassis configuration ----- " >> $REZULTAT
    echo $CONFIGURATIONLIST >> $REZULTAT
    IPLIST=$(snmp_call "walk" 2c $COMMUNITY $ip $IPADDRESS $HOSTNAME "Remote IP address")
    echo "----- Remote IP address ----- " >> $REZULTAT
    echo $IPLIST >> $REZULTAT
    end_time=$(date +%s.%N)
    time_sum=$(awk -v s="$start_host" -v e="$end_time" 'BEGIN {printf "%.3f", e - s}')
    
    # Upisujemo log da je sve zavrseno
    make_log "Zavrsena [$ip] $HOSTNAME"
    echo "==============================" >> $REZULTAT
    make_log "[$HOSTNAME] [$ip] Vreme obrade: $time_sum"
    make_log "=============================="
done


