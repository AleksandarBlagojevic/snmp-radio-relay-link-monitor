#!/bin/bash

# Pomocni file-ovi za pravljenje logova 
# Trenutno vreme i datum u formatu yyyymmdd_hhmm
VREME=$(date '+%Y%m%d_%H%M')
CERLOG="cer_info_$VREME.log"
NEDOSTUPNI="nedostupni_$VREME.txt"
REZULTAT="rezultat_$VREME.txt"
OUTPUT_FILE="topologija_$VREME.csv"
# Pravim te fajlove na pocetku
touch $CERLOG
touch $NEDOSTUPNI
touch $REZULTAT
touch $OUTPUT_FILE

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
    if [[ "$TYPE" != "Evolution" ]]; then
        INTERFACESLIST=$(snmp_call "walk" 2c $COMMUNITY $ip $INTERFACES $HOSTNAME "Physical Interfaces ifAlias")
        echo "----- Physical Interfaces ifAlias ----- " >> $REZULTAT
        echo $INTERFACESLIST >> $REZULTAT
    else
        echo "----- Physical Interfaces ifAlias ----- " >> $REZULTAT
        echo "$INTERFACES = No Such Object available on this agent at this OID" >> $REZULTAT
    fi
    if [[ "$TYPE" != "Evolution" ]]; then
        SERVICESLIST=$(snmp_call "walk" 2c $COMMUNITY $ip $SERVICES $HOSTNAME "Ethernet and TDM services")
        echo "----- Ethernet and TDM services ----- " >> $REZULTAT
        echo $SERVICESLIST >> $REZULTAT
    else
        echo "----- Ethernet and TDM services ----- " >> $REZULTAT
        echo "$SERVICES = No Such Object available on this agent at this OID" >> $REZULTAT
    fi
    if [[ "$TYPE" != "Evolution" && "$TYPE" != "IP-50C" ]]; then
        CONFIGURATIONLIST=$(snmp_call "walk" 2c $COMMUNITY $ip $CONFIGURATION $HOSTNAME "Chassis configuration")
        echo "----- Chassis configuration ----- " >> $REZULTAT
        echo $CONFIGURATIONLIST >> $REZULTAT
    else
        echo "----- Chassis configuration ----- " >> $REZULTAT
        echo "$CONFIGURATION = No Such Object available on this agent at this OID" >> $REZULTAT
    fi
    if [[ "$TYPE" != "Evolution" ]]; then
        IPLIST=$(snmp_call "walk" 2c $COMMUNITY $ip $IPADDRESS $HOSTNAME "Remote IP address")
        echo "----- Remote IP address ----- " >> $REZULTAT
        echo $IPLIST >> $REZULTAT
    else
        echo "----- Remote IP address ----- " >> $REZULTAT
        echo "$IPADDRESS = No Such Object available on this agent at this OID" >> $REZULTAT
    fi
    end_time=$(date +%s.%N)
    time_sum=$(awk -v s="$start_host" -v e="$end_time" 'BEGIN {printf "%.3f", e - s}')
    
    # Upisujemo log da je sve zavrseno
    make_log "Zavrsena [$ip] $HOSTNAME"
    echo "==============================" >> $REZULTAT
    make_log "[$HOSTNAME] [$ip] Vreme obrade: $time_sum"
    make_log "=============================="
done

# Obrisi prethodni rezultat ako postoji i dodaj header
echo "IP, Hostname, Element type, Physical Interfaces, Physical Interfaces Description, Ethernet and TDM services, Ethernet and TDM services Description, Chassis configuration, Chassis configuration Description, Remote IP address, Remote IP address Description" > "$OUTPUT_FILE"
awk '
BEGIN { 
    FS="\n"; 
    RS="=============================="; 
    OFS=";" 
    
    ### --- MAPA PHYSICAL INTERFACES ---
    name_phy_int["268443713"] = "Ethernet: Slot 1 Port 1"
    name_phy_int["268443714"] = "Ethernet: Slot 1 Port 2"
    name_phy_int["268443715"] = "Ethernet: Slot 1 Port 3"
    name_phy_int["268443716"] = "Ethernet: Slot 1 Port 4"
    name_phy_int["268443717"] = "Ethernet: Slot 1 Port 5"
    name_phy_int["268443718"] = "Ethernet: Slot 1 Port 6"
    name_phy_int["268476801"] = "TDM: Slot 1 Port 1"

    ### --- MAPA RADIO PORTOVA ---
    radio["268451905"] = "Radio: Slot 1 Port 1"
    radio["268451906"] = "Radio: Slot 1 Port 2"
    radio["268452033"] = "Radio: Slot 3 Port 1"
    radio["268452034"] = "Radio: Slot 3 Port 2"
    radio["268452097"] = "Radio: Slot 4 Port 1"
    radio["268452098"] = "Radio: Slot 4 Port 2"
    radio["268452161"] = "Radio: Slot 5 Port 1"
    radio["268452162"] = "Radio: Slot 5 Port 2"
    radio["268452163"] = "Radio: Slot 5 Port 3"
    radio["268452164"] = "Radio: Slot 5 Port 4"
    radio["268452225"] = "Radio: Slot 6 Port 1"
    radio["268452226"] = "Radio: Slot 6 Port 2"
    radio["268452227"] = "Radio: Slot 6 Port 3"
    radio["268452228"] = "Radio: Slot 6 Port 4"
    radio["268452289"] = "Radio: Slot 7 Port 1"
    radio["268452353"] = "Radio: Slot 8 Port 1"
    radio["268452417"] = "Radio: Slot 9 Port 1"
    radio["268452481"] = "Radio: Slot 10 Port 1"

}

# Za svaki blok
{
    # Preskoci prazne blokove
    if (length($0) == 0) {next}
    ip = ""; hostname = ""; type = ""; type_name = ""

    # Uzmi liniju koja sadrzi IP i ime
    if (match($2, /\[([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\][ \t]+(.+)$/,m)) {
        ip = m[1]
        hostname = m[2]
    }

    # Sledeca linija $3 je type
    type_name = $3
    print ip "@" hostname "@" type_name "@@@@@@@@"


    line = $5
    while(match(line, /\.([0-9]+)[ ]*=[ ]*STRING[ ]*:[ ]*"([^"]+)"/, m)) {
        id = m[1]
        text = m[2]
        if (id in name_phy_int) {
            name = name_phy_int[id]
        } 
        #gsub(/^STRING: */, "", vrednost)
        #gsub(/^"|"$/, "", vrednost)
        print ip "@" hostname "@" type_name "@" name "@" text "@@@@@@"
        line = substr(line, RSTART + RLENGTH)
    }
    line = $5
    while(match(line, /\.([0-9]+)[ ]*=[ ]*"([^"]+)"/, m)) {
        id = m[1]
        text = m[2]
        if (id in name_phy_int) {
            name = name_phy_int[id]
        } 
        print ip "@" hostname "@" type_name "@" name "@" text "@@@@@@"
        line = substr(line, RSTART + RLENGTH)
    }


    line = $7
    while(match(line, /\.([0-9]+)[ ]*=[ ]*STRING[ ]*:[ ]*"([^"]+)"/, m)) {
        id = m[1]
        text = m[2] 
        print ip "@" hostname "@" type_name "@@@Service ID:" id "@" text "@@@@" 
        line = substr(line, RSTART + RLENGTH)
    }
    line = $7
    while(match(line, /\.([0-9]+)[ ]*=[ ]*"([^"]+)"/, m)) {
        id = m[1]
        text = m[2]
        print ip "@" hostname "@" type_name "@@@Service ID:" id "@" text "@@@@" 
        line = substr(line, RSTART + RLENGTH)
    }

    line = $9
    while(match(line, /\.([0-9]+)[ ]*=[ ]*STRING[ ]*:[ ]*"([^"]+)"/, m)) {
        id = m[1]
        text = m[2] 
        print ip "@" hostname "@" type_name "@@@@@Service ID:" id "@" text "@@" 
        line = substr(line, RSTART + RLENGTH)
    }
    line = $9
    while(match(line, /\.([0-9]+)[ ]*=[ ]*"([^"]+)"/, m)) {
        id = m[1]
        text = m[2]
        print ip "@" hostname "@" type_name "@@@@@Service ID:" id "@" text "@@" 
        line = substr(line, RSTART + RLENGTH)
    }

    line = $11
    while (match(line, /\.([0-9]+)[ ]*=[ ]*IpAddress[ ]*:[ ]*([0-9.]+)/, m)) {
        id = m[1]
        name = m[1]
        if (id in radio) {
            name = radio[id]
        } 
        text = m[2] 
        print ip "@" hostname "@" type_name "@@@@@@@" name "@" text
        line = substr(line, RSTART + RLENGTH)
    }
    line = $11
    while (match(line, /\.([0-9]+)[ ]*=[ ]*([0-9.]+)/, m)) {
        id = m[1]
        name = m[1]
        if (id in radio) {
            name = radio[id]
        } 
        text = m[2] 
        print ip "@" hostname "@" type_name "@@@@@@@" name "@" text
        line = substr(line, RSTART + RLENGTH)
    }

    line = $11
    # while (match(line, /\.([0-9]+)[ ]*=[ ]*STRING[ ]*:[ ]*([0-9.]+)/, m)) {
    # id = m[1]
    #     name = m[1]
    #     if (id in radio) {
    #         name = radio[id]
    #     } 
    #     text = m[2] 
    #     print ip "@" hostname "@" type_name "@@@@@@@" name "@" text 
    #     line = substr(line, RSTART + RLENGTH)
    # }
    
    


   
    
}
' $REZULTAT >> $OUTPUT_FILE



make_log "CSV generisan: $OUTPUT_FILE"

make_log "ZAVRSENA SKRIPTA "
echo "ZAVRSENA SKRIPTA "
