#!/bin/bash

# Pomocni file-ovi za pravljenje logova 
# Trenutno vreme i datum u formatu yyyymmdd_hhmm
VREME=$(date '+%Y%m%d_%H%M')
NECLOG="nec_info_$VREME.log"
NEDOSTUPNI="nedostupni_neo_$VREME.txt"
NEDOSTUPNINEO="nedostupni_v4_$VREME.txt"
NEDOSTUPNIV4="nedostupni_$VREME.txt"
REZULTAT="rezultat_$VREME.txt"
OUTPUT_FILE="topologija_$VREME.csv"
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

#COMMUNITY_IPSO=
#COMMUNITY=

echo "==============================" >> $REZULTAT
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



# Obrisi prethodni rezultat ako postoji i dodaj header
echo "IP, Hostname, Element type, MODEM, MODEM name, ETH, ETH name, VLAN ID, VLAN name, MODEM cross, MODEM VLANID cross, ETH cross, ETH VLANID cross, ETH VLANID1" > "$OUTPUT_FILE"
awk '
BEGIN { FS="\n"; RS="=============================="; OFS=";" }

# Za svaki blok
{
    # Preskoci prazne blokove
    if (length($0) == 0) {next}
    ip = ""; hostname = ""; type = ""; type_name = ""

    # Uzmi liniju koja sadrzi IP i ime
    if (match($2, /\[[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\][ \t]+"[^"]+"/)) {
        line = substr($2, RSTART, RLENGTH)

        # Izvuci IP
        if (match(line, /\[[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\]/)) {
            ip = substr(line, RSTART+1, RLENGTH-2)  # +1 i -2 da se sklone zagrade
        }

        # Izvuci ime
        if (match(line, /"[^"]+"/)) {
            hostname = substr(line, RSTART+1, RLENGTH-2) # ukloni navodnike
        }

    }

    # Sledeca linija $3 je type
    type = $3
    if (type == "100") {
        type_name = "PASOLINK NEO"
    } else if (type == "520") {
        type_name = "iPASOLINK EX"
    } else if (type == "1000") {
        type_name = "iPASOLINK 1000" 
    } else if (type == "210") {
        type_name = "iPASOLINK 200"
    } else if (type == "400") {
        type_name = "iPASOLINK 400"
    } else if (type == "200") {
        type_name = "iPASOLINK 200"
    } else if (type == "10520") {
        type_name = "iPASOLINK EX/A"
    } else if (type == "10400") {
        type_name = "iPASOLINK VR4"
    } else if (type == "10200") {
        type_name = "iPASOLINK V2"
    } else if (type == "11000") {
        type_name = "iPASOLINK VR10"
    } else {
        type_name = "PASOLINK V4"
    }

    print ip "," hostname "," type_name ",,,,,,,,,,,"

    

    line = $7
    while(match(line, /\.([0-9]+)[ ]*=[ ]*STRING:[ ]*"([^"]+)"/, m)) {
        modem = m[1]
        modem_name = m[2]

        if (modem == "16842752") {
            modem_num = "MODEM 1"
        } else if (modem == "25231360") {
            modem_num = "MODEM 2"
        } else if (modem == "33619968") {
            modem_num = "MODEM 3"
        } else if (modem == "42008576") {
            modem_num = "MODEM 4"
        } else if (modem == "50397184") {
            modem_num = "MODEM 5"
        } else if (modem == "58785792") {
            modem_num = "MODEM 6"
        } else if (modem == "67174400") {
            modem_num = "MODEM 7"
        } else if (modem == "75563008") {
            modem_num = "MODEM 8"
        } else if (modem == "100728832") {
            modem_num = "MODEM 11"
        } else if (modem == "109117440") {
            modem_num = "MODEM 12"
        } else if (modem == "117506048") {
            modem_num = "MODEM 13"
        } else {
            modem_num = modem
        }

        print ip "," hostname "," type_name "," modem_num "," modem_name ",,,,,,,,,"

        line = substr(line, RSTART + RLENGTH)


    }

    line = $7
    while(match(line, /\.([0-9]+)[ ]*=[ ]*"([^"]+)"/, m)) {
        modem = m[1]
        modem_name = m[2]

        if (modem == "16842752") {
            modem_num = "MODEM 1"
        } else if (modem == "25231360") {
            modem_num = "MODEM 2"
        } else if (modem == "33619968") {
            modem_num = "MODEM 3"
        } else if (modem == "42008576") {
            modem_num = "MODEM 4"
        } else if (modem == "50397184") {
            modem_num = "MODEM 5"
        } else if (modem == "58785792") {
            modem_num = "MODEM 6"
        } else if (modem == "67174400") {
            modem_num = "MODEM 7"
        } else if (modem == "75563008") {
            modem_num = "MODEM 8"
        } else if (modem == "100728832") {
            modem_num = "MODEM 11"
        } else if (modem == "109117440") {
            modem_num = "MODEM 12"
        } else if (modem == "117506048") {
            modem_num = "MODEM 13"
        } else {
            modem_num = modem
        }

        print ip "," hostname "," type_name "," modem_num "," modem_name ",,,,,,,,,"

        line = substr(line, RSTART + RLENGTH)


    }

    # ODAVDE ZA ETH
    line = $9
    #print line
    while (match(line, /\.([0-9]+)[ ]*=[ ]*STRING:[ ]*"([^"]+)"/, m)) {
        eth_id = m[1]
        eth_name = m[2]

        if (eth_id == "8454144") {
            eth_num = "ETH 1"
        } else if (eth_id == "142671872") {
            eth_num = "ETH 1"
        } else if (eth_id == "83951616") {
            eth_num = "ETH 1"
        }  else if (eth_id == "8519680") {
            eth_num = "ETH 2"
        } else if (eth_id == "142737408") {
            eth_num = "ETH 2"
        }  else if (eth_id == "84017152") {
            eth_num = "ETH 2"
        } else if (eth_id == "8585216") {
            eth_num = "ETH 3"
        }  else if (eth_id == "142802944") {
            eth_num = "ETH 3"
        } else if (eth_id == "84082688") {
            eth_num = "ETH 3"
        }  else if (eth_id == "8650752") {
            eth_num = "ETH 4"
        } else if (eth_id == "142868480") {
            eth_num = "ETH 4"
        }  else if (eth_id == "84148224") {
            eth_num = "ETH 4"
        } else if (eth_id == "8716288") {
            eth_num = "ETH 5"
        }  else if (eth_id == "142934016") {
            eth_num = "ETH 5"
        } else if (eth_id == "8781824") {
            eth_num = "ETH 6"
        }  else if (eth_id == "142999552") {
            eth_num = "ETH 6"
        } else if (eth_id == "143065088") {
            eth_num = "ETH 7"
        } else if (eth_id == "143130624") {
            eth_num = "ETH 8"
        } else {
            eth_num = eth_id
        }

        # ukloni STRING: i navodnike ako ih ima
        #gsub(/^STRING: */, "", vrednost)
        #gsub(/^"|"$/, "", vrednost)

        print ip "," hostname "," type_name ",,," eth_num "," eth_name ",,,,,,,"

        # odseci deo koji je vec pronadjen da bi nastavili dalje
        line = substr(line, RSTART + RLENGTH)
    }

    line = $9
    #print line
    while (match(line, /\.([0-9]+)[ ]*=[ ]*"([^"]+)"/, m)) {
        eth_id = m[1]
        eth_name = m[2]

        if (eth_id == "8454144") {
            eth_num = "ETH 1"
        } else if (eth_id == "142671872") {
            eth_num = "ETH 1"
        } else if (eth_id == "83951616") {
            eth_num = "ETH 1"
        }  else if (eth_id == "8519680") {
            eth_num = "ETH 2"
        } else if (eth_id == "142737408") {
            eth_num = "ETH 2"
        }  else if (eth_id == "84017152") {
            eth_num = "ETH 2"
        } else if (eth_id == "8585216") {
            eth_num = "ETH 3"
        }  else if (eth_id == "142802944") {
            eth_num = "ETH 3"
        } else if (eth_id == "84082688") {
            eth_num = "ETH 3"
        }  else if (eth_id == "8650752") {
            eth_num = "ETH 4"
        } else if (eth_id == "142868480") {
            eth_num = "ETH 4"
        }  else if (eth_id == "84148224") {
            eth_num = "ETH 4"
        } else if (eth_id == "8716288") {
            eth_num = "ETH 5"
        }  else if (eth_id == "142934016") {
            eth_num = "ETH 5"
        } else if (eth_id == "8781824") {
            eth_num = "ETH 6"
        }  else if (eth_id == "142999552") {
            eth_num = "ETH 6"
        } else if (eth_id == "143065088") {
            eth_num = "ETH 7"
        } else if (eth_id == "143130624") {
            eth_num = "ETH 8"
        } else {
            eth_num = eth_id
        }

        # ukloni STRING: i navodnike ako ih ima
        #gsub(/^STRING: */, "", vrednost)
        #gsub(/^"|"$/, "", vrednost)

        print ip "," hostname "," type_name ",,," eth_num "," eth_name ",,,,,,,"

        # odseci deo koji je vec pronadjen da bi nastavili dalje
        line = substr(line, RSTART + RLENGTH)
    }




    line = $5
    #print line
    while (match(line, /\.([0-9]+)[ ]*=[ ]*STRING:[ ]*"([^"]+)"/, m)) {
        vlan_id = m[1]
        vlan_name = m[2]

        # ukloni STRING: i navodnike ako ih ima
        #gsub(/^STRING: */, "", vrednost)
        #gsub(/^"|"$/, "", vrednost)

        print ip "," hostname "," type_name ",,,,," vlan_id "," vlan_name ",,,,,"

        # odseci deo koji je vec pronadjen da bi nastavili dalje
        line = substr(line, RSTART + RLENGTH)
    }

    line = $5
    #print line
    while (match(line, /\.([0-9]+)[ ]*=[ ]*"([^"]*)"/, m)) {
        vlan_id = m[1]
        vlan_name = m[2]

        print ip "," hostname "," type_name ",,,,," vlan_id "," vlan_name ",,,,,"

        # odseci deo koji je vec pronadjen da bi nastavili dalje
        line = substr(line, RSTART + RLENGTH)
    }

    line = $11
    while (match(line, /4\.([0-9]+)\.([0-9]+)[ ]*=[ ]*/, m)) {
        eth_modem = m[1]
        vlan_id = m[2]

        if (eth_modem == "16842752") {
            name = "MODEM 1"
        } else if (eth_modem == "25231360") {
            name = "MODEM 2"
        } else if (eth_modem == "33619968") {
            name = "MODEM 3"
        } else if (eth_modem == "42008576") {
            name = "MODEM 4"
        } else if (eth_modem == "50397184") {
            name = "MODEM 5"
        } else if (eth_modem == "58785792") {
            name = "MODEM 6"
        } else if (eth_modem == "67174400") {
            name = "MODEM 7"
        } else if (eth_modem == "75563008") {
            name = "MODEM 8"
        } else if (eth_modem == "100728832") {
            name = "MODEM 11"
        } else if (eth_modem == "109117440") {
            name = "MODEM 12"
        } else if (eth_modem == "117506048") {
            name = "MODEM 13"
        } else if (eth_modem == "8454144") {
            name = "ETH 1"
        } else if (eth_modem == "142671872") {
            name = "ETH 1"
        } else if (eth_modem == "83951616") {
            name = "ETH 1"
        }  else if (eth_modem == "8519680") {
            name = "ETH 2"
        } else if (eth_modem == "142737408") {
            name = "ETH 2"
        }  else if (eth_modem == "84017152") {
            name = "ETH 2"
        } else if (eth_modem == "8585216") {
            name = "ETH 3"
        }  else if (eth_modem == "142802944") {
            name = "ETH 3"
        } else if (eth_modem == "84082688") {
            name = "ETH 3"
        }  else if (eth_modem == "8650752") {
            name = "ETH 4"
        } else if (eth_modem == "142868480") {
            name = "ETH 4"
        }  else if (eth_modem == "84148224") {
            name = "ETH 4"
        } else if (eth_modem == "8716288") {
            name = "ETH 5"
        }  else if (eth_modem == "142934016") {
            name = "ETH 5"
        } else if (eth_modem == "8781824") {
            name = "ETH 6"
        }  else if (eth_modem == "142999552") {
            name = "ETH 6"
        } else if (eth_modem == "143065088") {
            name = "ETH 7"
        } else if (eth_modem == "143130624") {
            name = "ETH 8"
        } else {
            name = eth_modem
        }        

        print ip "," hostname "," type_name ",,,,,,," name "," vlan_id ",,,"

        # odseci deo koji je vec pronadjen da bi nastavili dalje
        line = substr(line, RSTART + RLENGTH)
    }

    

    line = $13
    while (match(line, /4\.([0-9]+)\.([0-9]+)[ ]*=[ ]*/, m)) {
        eth_modem = m[1]
        vlan_id = m[2]

        if (eth_modem == "16842752") {
            name = "MODEM 1"
        } else if (eth_modem == "25231360") {
            name = "MODEM 2"
        } else if (eth_modem == "33619968") {
            name = "MODEM 3"
        } else if (eth_modem == "42008576") {
            name = "MODEM 4"
        } else if (eth_modem == "50397184") {
            name = "MODEM 5"
        } else if (eth_modem == "58785792") {
            name = "MODEM 6"
        } else if (eth_modem == "67174400") {
            name = "MODEM 7"
        } else if (eth_modem == "75563008") {
            name = "MODEM 8"
        } else if (eth_modem == "100728832") {
            name = "MODEM 11"
        } else if (eth_modem == "109117440") {
            name = "MODEM 12"
        } else if (eth_modem == "117506048") {
            name = "MODEM 13"
        } else if (eth_modem == "8454144") {
            name = "ETH 1"
        } else if (eth_modem == "142671872") {
            name = "ETH 1"
        } else if (eth_modem == "83951616") {
            name = "ETH 1"
        }  else if (eth_modem == "8519680") {
            name = "ETH 2"
        } else if (eth_modem == "142737408") {
            name = "ETH 2"
        }  else if (eth_modem == "84017152") {
            name = "ETH 2"
        } else if (eth_modem == "8585216") {
            name = "ETH 3"
        }  else if (eth_modem == "142802944") {
            name = "ETH 3"
        } else if (eth_modem == "84082688") {
            name = "ETH 3"
        }  else if (eth_modem == "8650752") {
            name = "ETH 4"
        } else if (eth_modem == "142868480") {
            name = "ETH 4"
        }  else if (eth_modem == "84148224") {
            name = "ETH 4"
        } else if (eth_modem == "8716288") {
            name = "ETH 5"
        }  else if (eth_modem == "142934016") {
            name = "ETH 5"
        } else if (eth_modem == "8781824") {
            name = "ETH 6"
        }  else if (eth_modem == "142999552") {
            name = "ETH 6"
        } else if (eth_modem == "143065088") {
            name = "ETH 7"
        } else if (eth_modem == "143130624") {
            name = "ETH 8"
        } else {
            name = eth_modem
        }        

        print ip "," hostname "," type_name ",,,,,,," name "," vlan_id ",,,"

        # odseci deo koji je vec pronadjen da bi nastavili dalje
        line = substr(line, RSTART + RLENGTH)
    }

    

    line = $15
    while (match(line, /5\.([0-9]+)\.([0-9]+)\.([0-9]+)[ ]*=[ ]*/, m)) {
        eth_modem = m[1]
        vlan_id = m[2]
        vlan_tag = m[3]

        if (eth_modem == "16842752") {
            name = "MODEM 1"
        } else if (eth_modem == "25231360") {
            name = "MODEM 2"
        } else if (eth_modem == "33619968") {
            name = "MODEM 3"
        } else if (eth_modem == "42008576") {
            name = "MODEM 4"
        } else if (eth_modem == "50397184") {
            name = "MODEM 5"
        } else if (eth_modem == "58785792") {
            name = "MODEM 6"
        } else if (eth_modem == "67174400") {
            name = "MODEM 7"
        } else if (eth_modem == "75563008") {
            name = "MODEM 8"
        } else if (eth_modem == "100728832") {
            name = "MODEM 11"
        } else if (eth_modem == "109117440") {
            name = "MODEM 12"
        } else if (eth_modem == "117506048") {
            name = "MODEM 13"
        } else if (eth_modem == "8454144") {
            name = "ETH 1"
        } else if (eth_modem == "142671872") {
            name = "ETH 1"
        } else if (eth_modem == "83951616") {
            name = "ETH 1"
        }  else if (eth_modem == "8519680") {
            name = "ETH 2"
        } else if (eth_modem == "142737408") {
            name = "ETH 2"
        }  else if (eth_modem == "84017152") {
            name = "ETH 2"
        } else if (eth_modem == "8585216") {
            name = "ETH 3"
        }  else if (eth_modem == "142802944") {
            name = "ETH 3"
        } else if (eth_modem == "84082688") {
            name = "ETH 3"
        }  else if (eth_modem == "8650752") {
            name = "ETH 4"
        } else if (eth_modem == "142868480") {
            name = "ETH 4"
        }  else if (eth_modem == "84148224") {
            name = "ETH 4"
        } else if (eth_modem == "8716288") {
            name = "ETH 5"
        }  else if (eth_modem == "142934016") {
            name = "ETH 5"
        } else if (eth_modem == "8781824") {
            name = "ETH 6"
        }  else if (eth_modem == "142999552") {
            name = "ETH 6"
        } else if (eth_modem == "143065088") {
            name = "ETH 7"
        } else if (eth_modem == "143130624") {
            name = "ETH 8"
        } else {
            name = eth_modem
        }        

        print ip "," hostname "," type_name ",,,,,,,,," name "," vlan_id "," vlan_tag

        # odseci deo koji je vec pronadjen da bi nastavili dalje
        line = substr(line, RSTART + RLENGTH)
    }


   
    
}
' $REZULTAT >> $OUTPUT_FILE



make_log "CSV generisan: $OUTPUT_FILE"

make_log "ZAVRSENA SKRIPTA "
echo "ZAVRSENA SKRIPTA "
