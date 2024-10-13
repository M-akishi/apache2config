#!/bin/bash

# Comprobación de privilegios de root
if [ "$EUID" -ne 0 ]; then
    echo "Este script debe ejecutarse con privilegios de root."
    exit 1
fi

# Definición de funciones
apache2_first_setup() {
    # Actualizar el índice de paquetes
    apt update -y || {
        echo "Error al actualizar el índice de paquetes."
        exit 1
    }

    # Instalar Apache, Python y Node.js
    apt install apache2 python3 libapache2-mod-wsgi-py3 nodejs npm -y || {
        echo "Error en la instalación de Apache, Python o Node.js."
        exit 1
    }
}

apache2_sites_config() {
    local django_project_name="$1"
    local react_project_name="$2"
    echo "Configurando sitio Apache para los proyectos $django_project_name y $react_project_name..."

    site_conf="/etc/apache2/sites-available/${django_project_name}_and_${react_project_name}.conf"

    # Crear archivo de configuración
    cat <<EOL > "$site_conf"
<VirtualHost *:80>
    ServerAdmin admin@example.com
    DocumentRoot /var/www/html/$react_project_name/build

    <Directory /var/www/html/$react_project_name/build>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/react_error.log
    CustomLog \${APACHE_LOG_DIR}/react_access.log combined
</VirtualHost>

<VirtualHost *:81>
    Alias /static /var/www/html/$django_project_name/static/
    <Directory /var/www/html/$django_project_name/static>
        Require all granted
    </Directory>

    # Configuración WSGI para el proyecto Django
    WSGIDaemonProcess $django_project_name python-path=/var/www/html/$django_project_name python-home=/var/www/html/$django_project_name/venv
    WSGIProcessGroup $django_project_name
    WSGIScriptAlias / /var/www/html/$django_project_name/${django_project_name}/wsgi.py

    <Directory /var/www/html/$django_project_name/${django_project_name}>
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/django_error.log
    CustomLog \${APACHE_LOG_DIR}/django_access.log combined
</VirtualHost>
EOL

    echo "Listen 81" |  tee -a /etc/apache2/ports.conf > /dev/null
    echo "Configuración de puerto 81 agregada a ports.conf."

    a2ensite "${django_project_name}_and_${react_project_name}" || {
        echo "Error al habilitar el sitio ${django_project_name}_and_${react_project_name}."
        exit 1
    }

    systemctl reload apache2 || {
        echo "Error al reiniciar Apache."
        exit 1
    }
    echo "Sitio Apache configurado para los proyectos $django_project_name y $react_project_name."
}


django_add() {
    local project_name=$1
    local project_dir="/var/www/html/$project_name"

    if [ -d "$project_dir" ]; then
        echo "La carpeta $project_dir ya existe. Abortando."
        return 1
    fi

    mkdir -p "$project_dir"
    echo "Carpeta $project_dir creada."

    chown "$USER":"$USER" "$project_dir"
    chmod 755 "$project_dir"

    cd "$project_dir" || exit
    python3 -m venv venv
    echo "Entorno virtual creado en $project_dir/venv."

    source venv/bin/activate
    pip install --upgrade pip
    pip install django || {
        echo "Error al instalar Django."
        exit 1
    }
    echo "Django instalado en el entorno virtual."

    django-admin startproject "$project_name" . || {
        echo "Error al crear el proyecto Django."
        exit 1
    }
    echo "Proyecto Django $project_name creado en $project_dir."

    chown -R www-data:www-data "$project_dir"
    chmod -R 755 "$project_dir"

    echo "Proyecto Django configurado correctamente en $project_dir."
}

react_add() {
    local react_project_name=$1
    local react_project_dir="/var/www/html/$react_project_name"

    if [ -d "$react_project_dir" ]; then
        echo "La carpeta $react_project_dir ya existe. Abortando."
        return 1
    fi

    mkdir -p "$react_project_dir"
    echo "Carpeta $react_project_dir creada."

    chown "$USER":"$USER" "$react_project_dir"
    chmod 755 "$react_project_dir"

    cd "$react_project_dir" || exit
    npx create-react-app . || {
        echo "Error al crear la aplicación React."
        exit 1
    }
    echo "Aplicación React $react_project_name creada en $react_project_dir."

    npm run build || {
        echo "Error al compilar la aplicación React."
        exit 1
    }
    echo "Aplicación React compilada en modo producción."

    chown -R www-data:www-data "$react_project_dir"
    chmod -R 755 "$react_project_dir"
}

# Pregunta al usuario si desea configurar el servidor
read -p "¿Desea configurar un servidor Apache junto a Django y React? (s/n): " confirmation
confirmation=$(echo "$confirmation" | tr '[:upper:]' '[:lower:]')

if [[ "$confirmation" != "s" && "$confirmation" != "si" ]]; then
    echo "Saliendo del programa..."
    exit 0
fi

# Verificar si Apache está instalado
if systemctl list-units --type=service --all | grep -q 'apache2'; then
    echo "El servidor Apache ya está listo, configurando carpetas..."
else
    echo "El servidor Apache no está instalado, configurando..."
    apache2_first_setup
    echo "El servidor Apache ya está listo, configurando carpetas..."
fi

# Solicitar nombres de proyectos
read -p "Nombre del proyecto Django: " djangoproject
djangoproject=$(echo "$djangoproject" | sed 's/ //g')

read -p "Nombre del proyecto React: " reactproject
reactproject=$(echo "$reactproject" | sed 's/ //g')

# Configurar Apache
apache2_sites_config "$djangoproject" "$reactproject"

# Reiniciar Apache
systemctl restart apache2.service || {
    echo "Error al reiniciar el servidor Apache."
    exit 1
}

echo "¡Todo listo!"
