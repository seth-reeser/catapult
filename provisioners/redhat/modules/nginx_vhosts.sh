source "/catapult/provisioners/redhat/modules/catapult.sh"

# set variables from secrets/configuration.yml
mysql_user="$(echo "${configuration}" | shyaml get-value environments.$1.servers.redhat_mysql.mysql.user)"
mysql_user_password="$(echo "${configuration}" | shyaml get-value environments.$1.servers.redhat_mysql.mysql.user_password)"
mysql_root_password="$(echo "${configuration}" | shyaml get-value environments.$1.servers.redhat_mysql.mysql.root_password)"
redhat_ip="$(echo "${configuration}" | shyaml get-value environments.$1.servers.redhat.ip)"
redhat_mysql_ip="$(echo "${configuration}" | shyaml get-value environments.$1.servers.redhat_mysql.ip)"
company_email="$(echo "${configuration}" | shyaml get-value company.email)"

# create a vhost per website
echo "${configuration}" | shyaml get-values-0 websites.apache |
while IFS='' read -r -d '' key; do

    domain=$(echo "$key" | grep -w "domain" | cut -d ":" -f 2 | tr -d " ")
    domain_environment=$(echo "$key" | grep -w "domain" | cut -d ":" -f 2 | tr -d " ")
    if [ "$1" != "production" ]; then
        domain_environment=$1.$domain_environment
    fi
    domain_tld_override=$(echo "$key" | grep -w "domain_tld_override" | cut -d ":" -f 2 | tr -d " ")
    if [ ! -z "${domain_tld_override}" ]; then
        domain_root="${domain}.${domain_tld_override}"
    else
        domain_root="${domain}"
    fi
    domainvaliddbname=$(echo "$key" | grep -w "domain" | cut -d ":" -f 2 | tr -d " " | tr "." "_")
    force_auth=$(echo "$key" | grep -w "force_auth" | cut -d ":" -f 2 | tr -d " ")
    force_auth_exclude=$(echo "$key" | grep -w "force_auth_exclude" | tr -d " ")
    force_https=$(echo "$key" | grep -w "force_https" | cut -d ":" -f 2 | tr -d " ")
    software=$(echo "$key" | grep -w "software" | cut -d ":" -f 2 | tr -d " ")
    software_dbprefix=$(echo "$key" | grep -w "software_dbprefix" | cut -d ":" -f 2 | tr -d " ")
    software_workflow=$(echo "$key" | grep -w "software_workflow" | cut -d ":" -f 2 | tr -d " ")
    webroot=$(echo "$key" | grep -w "webroot" | cut -d ":" -f 2 | tr -d " ")

    # configure vhost
    if [ "$1" = "production" ]; then
        echo -e "\t * configuring vhost for ${domain_root}"
    else
        echo -e "\t * configuring vhost for ${1}.${domain_root}"
    fi
    sudo mkdir --parents /var/log/nginx/${domain_environment}
    sudo touch /var/log/nginx/${domain_environment}/access.log
    sudo touch /var/log/nginx/${domain_environment}/error.log
    # set domain_tld_override_alias_additions for vhost
    if [ -z "${domain_tld_override}" ]; then
        domain_tld_override_alias_additions=""
    else
        domain_tld_override_alias_additions="ServerAlias ${domain_environment}.${domain_tld_override}
        ServerAlias www.${domain_environment}.${domain_tld_override}"
    fi
    # handle the force_auth option
    if ([ ! -z "${force_auth}" ]) && ([ "$1" = "test" ] || [ "$1" = "qc" ] || [ "$1" = "production" ]); then
        if ([ ! -z "${force_auth_exclude}" ]); then
            force_auth_excludes=( $(echo "${key}" | shyaml get-values force_auth_exclude) )
            if ([[ "${force_auth_excludes[@]}" =~ "$1" ]]); then
                force_auth_value=""
            else
                sudo htpasswd -b -c /etc/httpd/sites-enabled/${domain_environment}.htpasswd ${force_auth} ${force_auth} 2>&1 | sed "s/^/\t\t/"
                force_auth_value="<Location />
                    # Force HTTP authentication
                    AuthType Basic
                    AuthName \"Authentication Required\"
                    AuthUserFile \"/etc/httpd/sites-enabled/${domain_environment}.htpasswd\"
                    Require valid-user
                </Location>"
            fi
        else
            sudo htpasswd -b -c /etc/httpd/sites-enabled/${domain_environment}.htpasswd ${force_auth} ${force_auth} 2>&1 | sed "s/^/\t\t/"
            force_auth_value="<Location />
                # Force HTTP authentication
                AuthType Basic
                AuthName \"Authentication Required\"
                AuthUserFile \"/etc/httpd/sites-enabled/${domain_environment}.htpasswd\"
                Require valid-user
            </Location>"
        fi
    else
        # never force_auth in dev
        force_auth_value=""
    fi
    # handle the force_https option
    if [ "${force_https}" = true ]; then
        force_https_value="Redirect Permanent / https://${domain_environment}"
        force_https_hsts="Header always set Strict-Transport-Security \"max-age=15768000\""
    else
        force_https_value=""
        force_https_hsts="# HSTS is only enabled when force_https=true"
    fi
    # write vhost apache conf file
    sudo cat > /etc/nginx/sites-enabled/${domain_environment}.conf << EOF

    server {
            server_name ${domain_environment};

            root DocumentRoot /var/www/repositories/apache/${domain}/${webroot};
            index index.html index.php;

            # set expiration of assets to MAX for caching
            location ~* \.(ico|css|js|gif|jpe?g|png)(\?[0-9]+)?$ {
                    expires max;
                    log_not_found off;
            }

            location / {
                    # Check if a file or directory index file exists, else route it to index.php.
                    try_files $uri $uri/ /index.php;
            }

            location ~* \.php$ {
                    fastcgi_pass 127.0.0.1:9000;
                    include fastcgi.conf;
            }
    }

EOF

done
# reload nginx
sudo systemctl reload nginx.service
sudo systemctl status nginx.service
