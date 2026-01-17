# Servicio Integrado de Directorio y Autenticación

Este proyecto implementa un prototipo funcional de una infraestructura de autenticación centralizada para la **Facultad de Ingeniería de Sistemas (FIS)**. Utiliza tecnologías de código abierto para simular un entorno de laboratorio real, integrando servicios de directorio, autenticación segura, resolución de nombres y sincronización de tiempo.

## 📋 Descripción del Proyecto

El sistema automatiza el despliegue y la configuración de los siguientes servicios en un servidor Linux (Ubuntu/Debian):

* **OpenLDAP (Slapd):** Directorio centralizado para almacenar usuarios, materias, profesores y activos (PCs).
* **Kerberos (KDC):** Protocolo de autenticación segura para validar identidades sin transmitir contraseñas en texto plano.
* **Bind9 (DNS):** Resolución de nombres local para el dominio `fis.epn.local`.
* **Chrony (NTP):** Sincronización de tiempo para asegurar la validez de los tickets Kerberos.

Además, incluye un **Script de Gestión en Bash** que actúa como interfaz principal para:

1. Aprovisionar el servidor desde cero.
2. Simular el inicio de sesión de estudiantes en los laboratorios.
3. Auditar accesos y detectar incidentes de seguridad.

## 🚀 Instalación y Despliegue

### Pasos de Instalación

1. **Clonar el repositorio:**
```bash
git clone https://github.com/ImYasid/JimenezY-Proyecto2.git
cd JimenezY-Proyecto2

```


2. **Dar permisos de ejecución al script:**
```bash
chmod +x JimenezY-Proyecto2.sh

```


3. **Ejecutar el script principal:**
```bash
sudo ./JimenezY-Proyecto2.sh

```

## ⚙️ Configuración y Uso

Al iniciar el script, verás un menú interactivo con las siguientes opciones:

### 1. ⚙️ Formatear y Reinstalar el Sistema

* **Qué hace:** Detiene todos los servicios, borra las bases de datos existentes (LDAP/Kerberos) y regenera toda la configuración desde cero.
* **Cuándo usarlo:** En la primera ejecución o si necesitas "resetear" el laboratorio a su estado de fábrica.
* **Datos generados:** Crea automáticamente 15 estudiantes aleatorios, 10 materias fijas, profesores asignados y 15 computadoras (Activos).

### 2. 🔄 Cambiar de PC

* **Qué hace:** Consulta al directorio LDAP para listar las computadoras disponibles (`P5-L3-PC01`, etc.).
* **Uso:** Permite seleccionar desde qué equipo se está simulando el acceso. Esto afecta los registros en el log de auditoría.

### 3. 🖥️ Simular Ingreso de Estudiante

* **Qué hace:** Muestra una lista de usuarios de prueba (Código y Contraseña) y solicita credenciales.
* **Validación:**
1. Verifica la contraseña contra **Kerberos**.
2. Verifica en **LDAP** si el estudiante tiene una materia inscrita en el horario actual.
3. Autoriza o deniega el acceso y guarda el evento en el log.

### 4. 📋 Reportes y Auditoría

* **Qué hace:** Permite visualizar los intentos de acceso (exitosos o fallidos).
* **Funcionalidad:** Puedes filtrar por la PC actual, buscar una PC específica (útil para informática forense) o ver el historial completo.

## 📂 Estructura del Repositorio

El proyecto mantiene una estructura limpia donde el script genera dinámicamente los archivos necesarios.

```text
JimenezY-Proyecto2/
├── proyecto_sistemas.sh      # Script principal (Instalador + Controlador)
├── README.md                 # Documentación del proyecto
├── config/                   # (Generado dinámicamente) Archivos .conf para servicios
│   ├── named.conf.local      # Configuración de Zona DNS
│   ├── db.fis.epn.local      # Zona Directa DNS
│   ├── krb5.conf             # Configuración del Reino Kerberos
│   └── chrony.conf           # Configuración de NTP
└── data/                     # (Generado dinámicamente) Archivos LDIF para LDAP
    ├── 1_estructura.ldif     # Estructura base (OUs: Estudiantes, Materias, etc.)
    ├── 2_profesores.ldif     # Datos de docentes
    ├── 3_activos.ldif        # Inventario de computadoras
    └── 4_materias.ldif       # Asignaturas y horarios

```

## 🛡️ Seguridad y Credenciales

Para efectos de prototipo académico, se utilizan las siguientes credenciales predeterminadas dentro del script:

* **Dominio:** `FIS.EPN.LOCAL`
* **Admin LDAP/Kerberos:** `admin` / `admin/admin`
* **Contraseña Maestra:** `Sistemas2026`
* **Log de Auditoría:** `/var/log/fis_auditoria.log`

## 👤 Autor

**Yasid Jiménez**
Facultad de Ingeniería de Sistemas (FIS) - EPN