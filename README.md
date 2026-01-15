# S.I.G.A.L. - Sistema Integrado de Gestión y Auditoría de Laboratorios

**Estudiante:** Yasid Jiménez  
**Materia:** Computación Distribuida  
**Facultad:** Ingeniería de Sistemas (FIS - EPN)

---

## 📋 Descripción del Proyecto
Este proyecto implementa un prototipo de infraestructura de **Identidad Centralizada** para los laboratorios de la FIS. El objetivo es sustituir las cuentas locales inseguras por un sistema distribuido que garantice:

1.  **No Repudio:** Autenticación estricta mediante **Kerberos V5**.
2.  **Trazabilidad:** Asociación de activos (PCs) con usuarios responsables mediante **OpenLDAP**.
3.  **Auditoría Forense:** Capacidad de identificar al responsable de un equipo en un momento específico (ej. en caso de daño de hardware).

## 🏗️ Arquitectura del Sistema
El sistema despliega los siguientes servicios integrados sobre Linux (Ubuntu/WSL):

* **Kerberos KDC:** Gestión de tickets (TGT/TGS) y autenticación segura.
* **OpenLDAP:** Directorio de usuarios (Estudiantes) y activos (Laboratorios/PCs).
* **BIND9 (DNS):** Resolución de nombres de dominio (`fis.epn.local`) necesaria para el protocolo Kerberos.
* **Chrony (NTP):** Sincronización de tiempo para evitar ataques de repetición.

## 🚀 Instalación y Despliegue

El despliegue está totalmente automatizado mediante el script `JimenezY-Proyecto2.sh`.

### Requisitos
* Ubuntu 20.04/22.04/24.04 (o WSL2).
* Permisos de Superusuario (Root).

### Pasos
1.  Clonar este repositorio.
2.  Dar permisos de ejecución al script:
    ```bash
    chmod +x JimenezY-Proyecto2.sh
    ```
3.  Ejecutar el instalador:
    ```bash
    sudo ./JimenezY-Proyecto2.sh
    ```

> **Nota:** El script realizará una limpieza de instalaciones previas de Kerberos/LDAP para garantizar un despliegue limpio.

## 🧪 Caso de Uso y Demostración (Automática)

Al finalizar la instalación, el script ejecuta automáticamente un **Simulacro de Auditoría** con el siguiente escenario real:

1.  **Incidente:** Se reporta un daño en el teclado de la máquina ubicada en el **Piso 5, Laboratorio 2, PC 01**.
2.  **Identificación:** El administrador consulta al sistema por el ID del activo (`P5-L2-PC01`).
3.  **Resultado:** El sistema cruza la información de LDAP y Kerberos para revelar el nombre y código único del estudiante responsable en ese horario.

### Credenciales de Prueba Generadas
* **Realm:** `FIS.EPN.LOCAL`
* **Admin Principal:** `admin/admin`
* **Usuario de Prueba:** `219001` (Yasid Jimenez)
* **Contraseña Maestra:** `Sistemas2026`
