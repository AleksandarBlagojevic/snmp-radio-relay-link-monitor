#!/bin/bash

# Pomocni file-ovi za pravljenje logova 
# Trenutno vreme i datum u formatu yyyymmdd_hhmm
VREME=$(date '+%Y%m%d_%H%M')
NECLOG="nec_info_$VREME.log"
NEDOSTUPNI="nedostupni_neo_$VREME.txt"
NEDOSTUPNINEO="nedostupni_v4_$VREME.txt"
NEDOSTUPNIV4="nedostupni_$VREME.txt"
REZULTAT="rezultat_$VREME.txt"
# Pravim te fajlove na pocetku
touch $NECLOG
touch $NEDOSTUPNI
touch $REZULTAT

# Funkcija koja pravi log u formatu "[datum_vreme] poruka"
make_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $NECLOG
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

echo "============================== POKRENUTA SKRIPTA ==============================" >> $NECLOG
# Iz pdt file izvlacimo sve ip adrese
INVENTORY="ipList.txt"

# Pronaji sve IP adrese u file-u, sortiraj ih ...
# Format ddd.ddd.ddd.ddd stim sto poslenji oktet nije 0
ip_command='grep -oP "Obj[0-9]+=([^ ]*)" $INVENTORY \
  | tr "," "\n" \
  | grep -E "[0-9]{3}\.[0-9]{3}\.[0-9]{3}\.([0-9][0-9][1-9]|[0-9][1-9][0-9]|[1-9][0-9][0-9])" \
  | sort -u \
  | cut -d= -f2 \
  | awk -F. '\''{printf "%d.%d.%d.%d\n",$1,$2,$3,$4}'\'''
readarray -t ip_array < <(eval "$ip_command")

# Pomocna fukncija za ispisivanje niza
#echo "Array elements:"
#for item in "${ip_array[@]}"; do
#  echo "$item" >> "ip_v1.txt"
#done



# SPISAK SVIH OIDA

#IPASO STANDARD
IPASOHOSTNAME=1.3.6.1.4.1.119.2.3.69.5.1.1.1.3.1
IPASOEQUIPMENTTYPE=1.3.6.1.4.1.119.2.3.69.1.1.13.0
IPASOVLANLIST=1.3.6.1.4.1.119.2.3.69.501.5.20.5.1.3
IPASOPORTMODEMNAME=1.3.6.1.4.1.119.2.3.69.501.5.5.1.1.3
IPASOPORTETHNAME=1.3.6.1.4.1.119.2.3.69.501.5.30.1.1.11
IPASOCROSSCONNECT=1.3.6.1.4.1.119.2.3.69.501.5.20.2.1.4
IPASOCROSSCONNECT1=1.3.6.1.4.1.119.2.3.69.501.5.20.3.1.4
IPASOVLANCROSSCONNECT=1.3.6.1.4.1.119.2.3.69.501.5.20.4.1.5

# NEO
NEOHOSTNAME=1.3.6.1.4.1.119.2.3.69.3.1.1.1.0
NEOEQUIPMENTTYPE=1.3.6.1.4.1.119.2.3.69.3.1.1.7.0

# V4
V4HOSTNAME=1.3.6.1.4.1.119.2.3.69.1.1.1.0

COMMUNITY_IPSO=necnms
COMMUNITY=public

# Prolazimo kroz sve IP adrese
for ip in "${ip_array[@]}"; do
    make_log "============================================================"
    make_log "Obrada $ip ..."
    # Prozivamo hostname
    start_host=$(date +%s.%N)
    HOSTNAME=$(snmp_call "get" 2c $COMMUNITY_IPSO $ip $IPASOHOSTNAME "" hostname)
    
    # Proveravamo da li je dostupan, ako nije nastavljamo sa drugom adresom
    if [[ -z "$HOSTNAME" ]]; then
        make_log "[$ip] NEDOSTUPAN — nema Hostname odgovora (${time_host}s)"
        echo "$ip" >> $NEDOSTUPNI
        make_log "Zavrsena [$ip] "
        make_log "=============================="
        continue
    fi
    # Upisujemo u rezultat
    echo "[$ip] $HOSTNAME" >> $REZULTAT
    # Prozivamo type
    start_type=$(date +%s.%N)
    EQUIPMENT=$(snmp_call "get" 2c $COMMUNITY_IPSO $ip $IPASOEQUIPMENTTYPE $HOSTNAME EquipmentType)
    # Mozda bi trebalo odraditi slicnu proveru kao kod HOSTNAME ... TODO
    # Upisujemo rezultat i pravimo log poruku
    echo $EQUIPMENT >> $REZULTAT
    # Prozivamo listu svih vlanova
    VLANLIST=$(snmp_call "walk" 2c $COMMUNITY_IPSO $ip $IPASOVLANLIST $HOSTNAME "vlan list")
    # Upisujemo rezultat i pravimo log poruku
    echo "----- vlan list ----- " >> $REZULTAT
    echo $VLANLIST >> $REZULTAT
    # Prozivamo listu PortModemName
    #time_modem=$(awk -v s="$start_modem" -v e="$end_modem" 'BEGIN {printf "%.3f", e - s}')
    MODEMLIST=$(snmp_call "walk" 2c $COMMUNITY_IPSO $ip $IPASOPORTMODEMNAME $HOSTNAME "modem list")
    # Upisujemo rezultat i pravimo log poruku
    echo "----- modem list ----- " >> $REZULTAT
    echo $MODEMLIST >> $REZULTAT
    # Prozivamo listu PortEthName
    ETHLIST=$(snmp_call "walk" 2c $COMMUNITY_IPSO $ip $IPASOPORTETHNAME $HOSTNAME "eth list")
    # Upisujemo rezultat i pravimo log poruku
    echo "----- eth list ----- " >> $REZULTAT
    echo $ETHLIST >> $REZULTAT
    # Prozivamo listu Crossconnect
    CROSSLIST=$(snmp_call "walk" 2c $COMMUNITY_IPSO $ip $IPASOCROSSCONNECT $HOSTNAME "cros list")
    # Upisujemo rezultat i pravimo log poruku
    echo "----- cros list ----- " >> $REZULTAT
    echo $CROSSLIST >> $REZULTAT
    # Prozivamo listu Crossconnect 1
    CROSSLIST1=$(snmp_call "walk" 2c $COMMUNITY_IPSO $ip $IPASOCROSSCONNECT1 $HOSTNAME "cros1 list")
    # Upisujemo rezultat i pravimo log poruku
    echo "----- cros list 1 ----- " >> $REZULTAT
    echo $CROSSLIST1 >> $REZULTAT
    # Prozivamo listu VLAN Crossconnect 
    CROSSLISTVLAN=$(snmp_call "walk" 2c $COMMUNITY_IPSO $ip $IPASOVLANCROSSCONNECT $HOSTNAME "cros vlan")
    end_crossvlan=$(date +%s.%N)
    time_sum=$(awk -v s="$start_host" -v e="$end_crossvlan" 'BEGIN {printf "%.3f", e - s}')
    # Upisujemo rezultat i pravimo log poruku
    echo "----- cros vlan  ----- " >> $REZULTAT
    echo $CROSSLISTVLAN >> $REZULTAT
    # Upisujemo log da je sve zavrseno
    make_log "Zavrsena [$ip] $HOSTNAME"
    echo "==============================" >> $REZULTAT
    make_log "[$HOSTNAME] [$ip] Vreme obrade: $time_sum"
    make_log "=============================="
done

#OUTPUT="nec_basic.csv"
#echo "IP,Hostname,EquipmentType" > "$OUTPUT"
make_log "Pocinjem obradu NEO uredjaja"
touch $NEDOSTUPNINEO
# Prolazim kroz sve nedostupne da vidim da li je neki NEO ...
# Najpre ih ucitaj
readarray -t ip_nedostupne < $NEDOSTUPNI

for ip in "${ip_nedostupne[@]}"; do
    make_log "NEO Obrada $ip ..."
    # Prozivamo hostname
    start_host=$(date +%s.%N)
    HOSTNAME=$(snmp_call "get" 1 $COMMUNITY $ip $NEOHOSTNAME "" hostname)
    # Proveravamo da li je dostupan
    if [[ -z "$HOSTNAME" ]]; then
        make_log "[$ip] NEDOSTUPAN — nema Hostname odgovora (${time_host}s)"
        echo "$ip" >> $NEDOSTUPNINEO
        make_log "Zavrsena [$ip] "
        continue
    fi
    # Upisujemo u rezultat
    echo "[$ip] $HOSTNAME" >> $REZULTAT
    make_log "[$HOSTNAME] Vreme odgovora hostname: ${time_host}s "
    # Prozivamo type
    EQUIPMENT=$(snmp_call "get" 1 $COMMUNITY $ip $NEOEQUIPMENTTYPE $HOSTNAME EquipmentType)
    end_type=$(date +%s.%N)
    time_sum=$(awk -v s="$start_host" -v e="$end_type" 'BEGIN {printf "%.3f", e - s}')
    echo $EQUIPMENT >> $REZULTAT
    make_log "Zavrsena [$ip] $HOSTNAME"
    echo "==============================" >> $REZULTAT
    make_log "[$HOSTNAME] [$ip] Vreme obrade: $time_sum"
    make_log "=============================="
done

make_log "Pocinjem obradu v4 uredjaja"
touch $NEDOSTUPNIV4
# Prolazim kroz sve nedostupne da vidim da li je neki V4 ...
# Najpre ih ucitaj
readarray -t ip_nedostupneneo < $NEDOSTUPNINEO

for ip in "${ip_nedostupneneo[@]}"; do
    make_log "V4 Obrada $ip ..."
    # Prozivamo hostname
    start_host=$(date +%s.%N)
    HOSTNAME=$(snmp_call "get" 1 $COMMUNITY $ip $V4HOSTNAME "" hostname)
    end_host=$(date +%s.%N)
    time_host=$(awk -v s="$start_host" -v e="$end_host" 'BEGIN {printf "%.3f", e - s}')
    # Proveravamo da li je dostupan
    if [[ -z "$HOSTNAME" ]]; then
        make_log "[$ip] NEDOSTUPAN — nema Hostname odgovora (${time_host}s)"
        echo "$ip" >> $NEDOSTUPNIV4
        make_log "Zavrsena [$ip] "
        continue
    fi
    # Upisujemo u rezultat
    echo "[$ip] $HOSTNAME" >> $REZULTAT
    make_log "Zavrsena [$ip] $HOSTNAME"
    echo "==============================" >> $REZULTAT
    make_log "[$HOSTNAME] [$ip] Vreme obrade: $time_host"
done
make_log "Zavrsena skripta prozivanja uredjaja"
make_log "Pravim CSV file"
echo "ZAVRSENA SKRIPTA "
