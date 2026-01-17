#!/bin/bash
# ==============================================================================
# PROYECTO: Servicio Integrado de Directorio y Autenticación
# AUTOR: Yasid Jiménez
# ==============================================================================

BASE_DIR=$(pwd)
PASS_ADMIN="Sistemas2026"
LOG_FILE="/var/log/fis_auditoria.log"
PC_ID_ACTUAL="P5-L3-PC01" 

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- VALIDACIÓN INICIAL ---
if [ ! -d "$BASE_DIR/data" ]; then
    mkdir -p "$BASE_DIR/data" "$BASE_DIR/config"
fi

# ==============================================================================
# SECCIÓN 1: SETUP DEL SISTEMA (DNS, NTP, KERBEROS, LDAP)
# ==============================================================================
setup_sistema() {
    echo -e "${BLUE}>>> INICIANDO SETUP DEL SISTEMA...${NC}"

    # Limpieza de entorno
    systemctl stop slapd krb5-kdc krb5-admin-server bind9 chrony > /dev/null 2>&1
    killall slapd > /dev/null 2>&1
    rm -rf /var/lib/krb5kdc/* /var/lib/ldap/* /etc/ldap/slapd.d/* /var/lib/bind/*
    rm -f /tmp/*.ldif /tmp/*.txt
    
    if [ ! -f "$LOG_FILE" ]; then touch $LOG_FILE; fi
    chmod 666 $LOG_FILE

    # Instalación de dependencias
    export DEBIAN_FRONTEND=noninteractive
    if ! command -v slapd &> /dev/null; then
        echo -e "${YELLOW}[SETUP] Instalando paquetes necesarios...${NC}"
        apt-get update -qq && apt-get install -y chrony bind9 ldap-utils krb5-kdc krb5-admin-server slapd > /dev/null 2>&1
    fi

    # Configuración de Host
    hostnamectl set-hostname srv-fis
    sed -i "/srv-fis/d" /etc/hosts
    echo "127.0.0.1 srv-fis.fis.epn.local srv-fis" >> /etc/hosts

    # Configuración DNS (Bind9)
    cat > "$BASE_DIR/config/named.conf.local" <<EOF
zone "fis.epn.local" { type master; file "/etc/bind/db.fis.epn.local"; };
EOF
    cat > "$BASE_DIR/config/db.fis.epn.local" <<EOF
\$TTL 604800
@ IN SOA srv-fis.fis.epn.local. root.srv-fis.fis.epn.local. ( 2 604800 86400 2419200 604800 )
@ IN NS srv-fis.fis.epn.local.
@ IN A 127.0.0.1
srv-fis IN A 127.0.0.1
EOF
    cp "$BASE_DIR/config/named.conf.local" /etc/bind/
    cp "$BASE_DIR/config/db.fis.epn.local" /etc/bind/
    echo 'options { directory "/var/cache/bind"; listen-on { 127.0.0.1; }; allow-query { any; }; recursion yes; dnssec-validation no; };' > /etc/bind/named.conf.options
    systemctl restart bind9

    # Configuración NTP (Chrony)
    cat > "$BASE_DIR/config/chrony.conf" <<EOF
pool 2.debian.pool.ntp.org iburst
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
EOF
    cp "$BASE_DIR/config/chrony.conf" /etc/chrony/
    systemctl restart chrony

    # Configuración Kerberos
    cat > "$BASE_DIR/config/krb5.conf" <<EOF
[libdefaults]
    default_realm = FIS.EPN.LOCAL
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 10h
    forwardable = true
[realms]
    FIS.EPN.LOCAL = {
        kdc = srv-fis.fis.epn.local
        admin_server = srv-fis.fis.epn.local
    }
EOF
    cp "$BASE_DIR/config/krb5.conf" /etc/krb5.conf
    printf "$PASS_ADMIN\n$PASS_ADMIN" | kdb5_util create -s 2>/dev/null
    echo "*/admin@FIS.EPN.LOCAL *" > /etc/krb5kdc/kadm5.acl
    systemctl restart krb5-kdc krb5-admin-server

    # Configuración LDAP
    echo "slapd slapd/domain string fis.epn.local" | debconf-set-selections
    dpkg-reconfigure -f noninteractive slapd > /dev/null 2>&1
    cat > /tmp/pass.ldif <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $PASS_ADMIN
EOF
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/pass.ldif > /dev/null 2>&1

    # --- GENERACIÓN DE DATOS ---
    echo -e "${YELLOW}[SETUP] Generando estructura y datos...${NC}"
    
    # 1. Estructura Base
    cat > "$BASE_DIR/data/1_estructura.ldif" <<EOF
dn: ou=FIS,dc=fis,dc=epn,dc=local
objectClass: organizationalUnit
ou: FIS

dn: ou=Estudiantes,ou=FIS,dc=fis,dc=epn,dc=local
objectClass: organizationalUnit
ou: Estudiantes

dn: ou=Materias,ou=FIS,dc=fis,dc=epn,dc=local
objectClass: organizationalUnit
ou: Materias

dn: ou=Profesores,ou=FIS,dc=fis,dc=epn,dc=local
objectClass: organizationalUnit
ou: Profesores

dn: ou=Activos,ou=FIS,dc=fis,dc=epn,dc=local
objectClass: organizationalUnit
ou: Activos
EOF

    # 2. Materias
    LISTA_MATERIAS=(
        "Computacion_Distribuida|07|09|Ing._Tomala"
        "Inteligencia_Artificial|07|09|Dra._Solis"
        "Programacion_Basica|09|11|Ing._Bravo"
        "Bases_de_Datos|09|11|Dr._Mera"
        "Redes_de_Computadoras|11|13|Ing._Cevallos"
        "Seguridad_Informatica|14|16|Ing._Vargas"
        "Desarrollo_Web|14|16|Ing._Lopez"
        "Calculo_Vectorial|16|18|Mat._Perez"
        "Etica_Profesional|16|18|Lic._Gomez"
        "Sistemas_Operativos|18|20|Ing._Zurita"
    )
    rm -f "$BASE_DIR/data/4_materias.ldif"
    GID_C=5000
    
    declare -gA MAPA_MATERIAS 
    declare -gA LISTA_MATERIAS_GLOBAL

    for ITEM in "${LISTA_MATERIAS[@]}"; do
        IFS="|" read -r NOM I F PROF <<< "$ITEM"
        cat <<EOF >> "$BASE_DIR/data/4_materias.ldif"
dn: cn=$NOM,ou=Materias,ou=FIS,dc=fis,dc=epn,dc=local
objectClass: posixGroup
cn: $NOM
gidNumber: $GID_C
description: Horario:$I-$F|Profesor:$PROF

EOF
        MAPA_MATERIAS[$GID_C]="$NOM ($I:00-$F:00)"
        LISTA_MATERIAS_GLOBAL[$GID_C]="$ITEM"
        ((GID_C++))
    done

    ldapadd -x -D "cn=admin,dc=fis,dc=epn,dc=local" -w $PASS_ADMIN -f "$BASE_DIR/data/1_estructura.ldif" > /dev/null 2>&1
    ldapadd -x -D "cn=admin,dc=fis,dc=epn,dc=local" -w $PASS_ADMIN -f "$BASE_DIR/data/4_materias.ldif" > /dev/null 2>&1

    # 3. Profesores
    rm -f "$BASE_DIR/data/2_profesores.ldif"
    
    for ITEM in "${LISTA_MATERIAS[@]}"; do
        IFS="|" read -r MATERIA INICIO FIN PROF_NOMBRE <<< "$ITEM"
        UID_PROF=$(echo "$PROF_NOMBRE" | sed 's/Ing._//;s/Dr._//;s/Lic._//;s/Mat._//' | tr '[:upper:]' '[:lower:]')
        
        cat <<EOF >> "$BASE_DIR/data/2_profesores.ldif"
dn: uid=$UID_PROF,ou=Profesores,ou=FIS,dc=fis,dc=epn,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: $PROF_NOMBRE
sn: Docente FIS
uid: $UID_PROF
uidNumber: $((3000 + RANDOM % 1000))
gidNumber: 5000
homeDirectory: /home/$UID_PROF
loginShell: /bin/bash
userPassword: {SASL}$UID_PROF
description: Encargado de $MATERIA
EOF
        kadmin.local -q "addprinc -pw Profesor123 $UID_PROF" > /dev/null 2>&1
    done
    ldapadd -x -D "cn=admin,dc=fis,dc=epn,dc=local" -w $PASS_ADMIN -f "$BASE_DIR/data/2_profesores.ldif" > /dev/null 2>&1

    # 4. Estudiantes
    rm -f /tmp/estudiantes.ldif /tmp/lista_usuarios.txt
    HORA_NUM=$((10#$(date +%H)))
    generar_codigo() { echo "$((2020 + RANDOM % 5))$(printf "%02d" $((1 + RANDOM % 12)))$(printf "%03d" $((RANDOM % 999)))"; }

    for i in {1..15}; do
        CODIGO=$(generar_codigo)
        CLAVE="Clave.$CODIGO"
        
        # Asignar materia compatible con la hora actual
        if [ $i -eq 1 ]; then
            GID_ELEGIDO=0
            GID_TEMP=5000
            for ITEM in "${LISTA_MATERIAS[@]}"; do
                IFS="|" read -r NOM I F PROF <<< "$ITEM"
                I_NUM=$((10#$I)); F_NUM=$((10#$F))
                if [ $HORA_NUM -ge $I_NUM ] && [ $HORA_NUM -lt $F_NUM ]; then
                    GID_ELEGIDO=$GID_TEMP; break
                fi
                ((GID_TEMP++))
            done
            if [ "$GID_ELEGIDO" == "0" ]; then GID_ELEGIDO=5000; fi
        else
            GID_ELEGIDO=$((5000 + RANDOM % 10))
        fi

        cat <<EOF >> /tmp/estudiantes.ldif
dn: uid=$CODIGO,ou=Estudiantes,ou=FIS,dc=fis,dc=epn,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Estudiante $CODIGO
sn: EPN
uid: $CODIGO
uidNumber: $((2000 + i))
gidNumber: $GID_ELEGIDO
homeDirectory: /home/$CODIGO
loginShell: /bin/bash
userPassword: {SASL}$CODIGO@FIS.EPN.LOCAL

EOF
        kadmin.local -q "addprinc -pw $CLAVE $CODIGO" > /dev/null 2>&1
        INFO="${MAPA_MATERIAS[$GID_ELEGIDO]}"
        printf "%-12s %-18s %-40s\n" "$CODIGO" "$CLAVE" "$INFO" >> /tmp/lista_usuarios.txt
    done
    ldapadd -x -D "cn=admin,dc=fis,dc=epn,dc=local" -w $PASS_ADMIN -f /tmp/estudiantes.ldif > /dev/null 2>&1
    
    # 5. Activos (PCs)
    rm -f "$BASE_DIR/data/3_activos.ldif"
    echo -e "${YELLOW}[SETUP] Inventariando activos de laboratorio...${NC}"

    NUM_PC=1
    while read -r LINEA; do
        CODIGO_EST=$(echo "$LINEA" | awk '{print $1}')
        NOMBRE_PC="P5-L3-PC$(printf "%02d" $NUM_PC)"
        
        cat <<EOF >> "$BASE_DIR/data/3_activos.ldif"
dn: cn=$NOMBRE_PC,ou=Activos,ou=FIS,dc=fis,dc=epn,dc=local
objectClass: device
objectClass: ipHost
objectClass: top
cn: $NOMBRE_PC
ipHostNumber: 192.168.50.$NUM_PC
description: Asignada a estudiante $CODIGO_EST
l: Laboratorio 3

EOF
        ((NUM_PC++))
    done < /tmp/lista_usuarios.txt

    ldapadd -x -D "cn=admin,dc=fis,dc=epn,dc=local" -w $PASS_ADMIN -f "$BASE_DIR/data/3_activos.ldif" > /dev/null 2>&1
    
    echo -e "${GREEN}✅ SISTEMA INSTALADO Y LISTO.${NC}"
    sleep 2
}

# ==============================================================================
# SECCIÓN 2: MÓDULO DE LOGIN
# ==============================================================================
modulo_login() {
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}   FACULTAD DE INGENIERÍA DE SISTEMAS - ACCESO A LABORATORIOS   ${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo -e "EQUIPO: $PC_ID_ACTUAL | FECHA: $(date)"
    echo -e "\n${GREEN}>>> USUARIOS DISPONIBLES <<<${NC}"
    printf "%-12s %-18s %-40s\n" "CÓDIGO" "CONTRASEÑA" "MATERIA INSCRITA"
    echo "-------------------------------------------------------------------------------------"
    cat /tmp/lista_usuarios.txt
    echo "-------------------------------------------------------------------------------------"

    while true; do
        echo -e "\n${CYAN}>> [LOGIN] Ingrese Código Único (o 'menu' para volver):${NC}"
        read -p "User: " USUARIO
        if [ "$USUARIO" == "menu" ]; then break; fi

        kinit $USUARIO 2>/dev/null
        if [ $? -eq 0 ]; then
            # Validación LDAP
            GID_USER=$(ldapsearch -x -LLL -D "cn=admin,dc=fis,dc=epn,dc=local" -w "$PASS_ADMIN" -b "ou=Estudiantes,ou=FIS,dc=fis,dc=epn,dc=local" "(uid=$USUARIO)" gidNumber 2>/dev/null | grep "gidNumber" | awk '{print $2}')
            
            if [ -z "$GID_USER" ]; then
                echo -e "${RED}Error de Sincronización LDAP.${NC}"; kdestroy >/dev/null 2>&1; continue
            fi

            DATA_MAT=$(ldapsearch -x -LLL -D "cn=admin,dc=fis,dc=epn,dc=local" -w "$PASS_ADMIN" -b "ou=Materias,ou=FIS,dc=fis,dc=epn,dc=local" "(gidNumber=$GID_USER)" cn description 2>/dev/null)
            NOM_MAT=$(echo "$DATA_MAT" | grep "cn:" | awk '{print $2}')
            DESC=$(echo "$DATA_MAT" | grep "description:")
            
            INICIO=$(echo "$DESC" | cut -d: -f3 | cut -d- -f1)
            FIN=$(echo "$DESC" | cut -d- -f2 | cut -d\| -f1)
            PROF=$(echo "$DESC" | cut -d: -f4)
            
            # Verificación de Horario
            H_NOW=$((10#$(date +%H)))
            I_NUM=$((10#$INICIO)); F_NUM=$((10#$FIN))
            
            if [ $H_NOW -ge $I_NUM ] && [ $H_NOW -lt $F_NUM ]; then
                echo -e "${GREEN}✅ ACCESO AUTORIZADO${NC}"
                echo "   Bienvenido, Estudiante $USUARIO."
                echo "   Usted está en la clase de: $NOM_MAT"
                echo "[$(date "+%Y-%m-%d %H:%M:%S")] SUCCESS | User:$USUARIO | PC:$PC_ID_ACTUAL | Materia:$NOM_MAT | Resp:$PROF" >> $LOG_FILE
            else
                echo -e "${RED}⛔ DENEGADO (Fuera de Horario)${NC}"
                echo "   Su clase es de $INICIO:00 a $FIN:00."
                echo "[$(date "+%Y-%m-%d %H:%M:%S")] DENIED  | User:$USUARIO | PC:$PC_ID_ACTUAL | Reason:OutOfSchedule" >> $LOG_FILE
            fi
            kdestroy >/dev/null 2>&1
        else
            echo -e "${RED}❌ Contraseña Incorrecta.${NC}"
            echo "[$(date "+%Y-%m-%d %H:%M:%S")] FAILED  | User:$USUARIO | PC:$PC_ID_ACTUAL | Reason:BadPassword" >> $LOG_FILE
        fi
    done
}

# ==============================================================================
# SECCIÓN 3: MÓDULO DE REPORTES
# ==============================================================================
modulo_reportes() {
    while true; do
        clear
        echo -e "${YELLOW}================================================================${NC}"
        echo -e "${YELLOW}   SISTEMA DE AUDITORÍA - BÚSQUEDA DE INCIDENTES                ${NC}"
        echo -e "${YELLOW}================================================================${NC}"
        echo -e "Archivo de Logs: $LOG_FILE\n"
        echo -e "Opciones:"
        echo "1. Ver reporte de la PC actual ($PC_ID_ACTUAL)"
        echo "2. Buscar por ID de otra PC"
        echo "3. Ver todo el historial completo"
        echo "4. Volver al menú principal"
        
        read -p "Seleccione: " OPCION_REP

        case $OPCION_REP in
            1) TARGET=$PC_ID_ACTUAL ;;
            2) read -p "Ingrese el ID de la PC dañada (ej. P5-L3-PC01): " TARGET ;;
            3) TARGET="" ;;
            4) return ;;
            *) continue ;;
        esac

        echo -e "\n${BLUE}>>> GENERANDO REPORTE DE ACTIVIDAD...${NC}"
        echo "----------------------------------------------------------------------------------"
        printf "%-20s | %-10s | %-12s | %-15s | %-20s\n" "FECHA" "ESTADO" "USUARIO" "PC" "DETALLE"
        echo "----------------------------------------------------------------------------------"
        
        if [ -z "$TARGET" ]; then
            grep "|" $LOG_FILE | tail -n 10 | awk -F "|" '{printf "%-20s | %-10s | %-12s | %-15s | %-20s\n", $1, $2, $3, $4, $5}'
        else
            RESULTADO=$(grep "$TARGET" $LOG_FILE)
            if [ -z "$RESULTADO" ]; then
                echo -e "${RED}No se encontraron registros para la PC: $TARGET${NC}"
            else
                echo "$RESULTADO" | awk -F "|" '{printf "%-20s | %-10s | %-12s | %-15s | %-20s\n", $1, $2, $3, $4, $5}'
            fi
        fi
        echo "----------------------------------------------------------------------------------"
        read -p "Presione ENTER para continuar..."
    done
}

# ==============================================================================
# FUNCIÓN EXTRA: SELECCIONAR PC
# ==============================================================================
seleccionar_pc() {
    clear
    echo -e "${BLUE}>>> CONSULTANDO EQUIPOS DISPONIBLES EN DIRECTORIO ACTIVO...${NC}"
    
    LISTA_PCS=$(ldapsearch -x -LLL -D "cn=admin,dc=fis,dc=epn,dc=local" -w "$PASS_ADMIN" -b "ou=Activos,ou=FIS,dc=fis,dc=epn,dc=local" "(objectClass=device)" cn | grep "^cn:" | awk '{print $2}' | sort)
    
    if [ -z "$LISTA_PCS" ]; then
        echo -e "${RED}❌ No se encontraron PCs en el sistema. Ejecute el paso 1 (Setup) primero.${NC}"
        read -p "Presione ENTER para volver..."
        return
    fi

    echo -e "${YELLOW}Seleccione la PC que desea simular:${NC}"
    echo "----------------------------------------"
    PC_ARRAY=($LISTA_PCS)
    INDICE=1
    for PC in "${PC_ARRAY[@]}"; do
        echo -e " $INDICE) ${CYAN}$PC${NC}"
        ((INDICE++))
    done
    echo "----------------------------------------"
    read -p "Ingrese el número de PC: " SELECCION

    REAL_INDEX=$((SELECCION - 1))
    if [ $REAL_INDEX -ge 0 ] && [ $REAL_INDEX -lt ${#PC_ARRAY[@]} ]; then
        PC_ID_ACTUAL=${PC_ARRAY[$REAL_INDEX]}
        echo -e "\n${GREEN}✅ Simulando desde: $PC_ID_ACTUAL${NC}"
    else
        echo -e "\n${RED}Opción inválida.${NC}"
    fi
    sleep 1.5
}

# ==============================================================================
# SECCIÓN 4: MENÚ PRINCIPAL
# ==============================================================================
setup_sistema # Check de dependencias al inicio

while true; do
    clear
    echo -e "${CYAN}****************************************************************${NC}"
    echo -e "${CYAN}*                   MENÚ PRINCIPAL                             *${NC}"
    echo -e "${CYAN}****************************************************************${NC}"
    echo -e "PC ACTUAL: ${YELLOW}$PC_ID_ACTUAL${NC}" 
    echo -e "----------------------------------------------------------------"
    echo -e "1. ⚙️  Formatear y Reinstalar el Sistema"
    echo -e "2. 🔄  Cambiar de PC"
    echo -e "3. 🖥️  Simular Ingreso de Estudiante"
    echo -e "4. 📋  Reportes y Auditoría"
    echo -e "5. 🚪  Salir"
    echo -e "----------------------------------------------------------------"
    read -p "Seleccione una opción [1-5]: " OPCION

    case $OPCION in
        1) setup_sistema ;;
        2) seleccionar_pc ;;
        3) modulo_login ;;
        4) modulo_reportes ;;
        5)
            echo -e "${GREEN}Apagando sistema... ¡Hasta luego!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción no válida.${NC}"
            sleep 1
            ;;
    esac
done