source "/catapult/provisioners/redhat/modules/catapult.sh"

# functions

hex2bin() {
  # Remove spaces, add leading zero, escape as hex string and parse with printf
  printf -- "$(cat | sed --regexp-extended --expression='s/[[:space:]]//g' --expression='s/^(.(.{2})*)$/0\1/' -e 's/(.{2})/\\x\1/g')"
}

urlbase64() {
  # urlbase64: base64 encoded string with '+' replaced with '-' and '/' replaced with '_'
  openssl base64 -e | tr --delete '\n\r' | sed --regexp-extended --expression='s:=*$::g' --expression='y:+/:-_:'
}

send_signed_request() {

    url=$1
    payload=$2

    payload64="$(printf '%s' "${payload}" | urlbase64)"
    #echo "payload64:" $payload64

    nonce=$(curl --head --show-error --connect-timeout 5 --max-time 5 --silent --request GET https://acme-staging.api.letsencrypt.org/directory | grep "^Replay-Nonce:" | sed s/\\r//|sed s/\\n//| cut -d ' ' -f 2)
    #echo "nonce:" $nonce

    header='{"alg": "RS256", "jwk": {"e": "'"${pub_exp64}"'", "kty": "RSA", "n": "'"${pub_mod64}"'"}}'
    #echo "header:" $header

    protected='{"alg": "RS256", "jwk": {"e": "'"${pub_exp64}"'", "kty": "RSA", "n": "'"${pub_mod64}"'"}, "nonce": "'"${nonce}"'"}'
    protected64="$(printf '%s' "${protected}" | urlbase64)"
    #echo "protected64:" $protected64

    signed64="$(printf '%s' "${protected64}.${payload64}" | openssl dgst -sha256 -sign "/catapult/secrets/id_rsa" | urlbase64)"
    #echo "signed64:" $signed64

    body='{"header": '"${header}"', "protected": "'"${protected64}"'", "payload": "'"${payload64}"'", "signature": "'"${signed64}"'"}'
    #echo "body:" $body

    response=$(curl --show-error --connect-timeout 5 --max-time 5 --silent --request POST --data "$body" --write-out "HTTPSTATUS:%{http_code}" $url)
    response_status=$(echo "${response}" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    response=$(echo "${response}" | sed -e 's/HTTPSTATUS\:.*//g')

}


# variables

domain=$(catapult websites.apache.$5.domain)
echo "domain:" $domain

# generate domain key
if [ ! -f "/etc/ssl/certs/${domain}/${domain}.key" ]; then
    openssl genrsa "4096" > "/etc/ssl/certs/${domain}/${domain}.key"
fi

# generate domain csr
#SANLIST="subjectAltName=DNS:${domain},DNS:${domain},DNS:${domain},etc..."
SANLIST="subjectAltName=DNS:${domain}"
openssl req -new -sha256 -key "/etc/ssl/certs/${domain}/${domain}.key" -subj "/" -reqexts SAN -config <(cat "/etc/pki/tls/openssl.cnf" <(printf "[SAN]\n%s" "$SANLIST")) > "/etc/ssl/certs/${domain}/${domain}.csr"

pub_exp64=$(openssl rsa -in "/catapult/secrets/id_rsa" -noout -text | grep publicExponent | grep -oE "0x[a-f0-9]+" | cut -d'x' -f2 | hex2bin | urlbase64)
#echo "pub_exp64:" $pub_exp64

pub_mod64=$(openssl rsa -in "/catapult/secrets/id_rsa" -noout -modulus | cut -d'=' -f2 | hex2bin | urlbase64)
#echo "pub_mod64:" $pub_mod64

thumbprint="$(printf '{"e":"%s","kty":"RSA","n":"%s"}' "${pub_exp64}" "${pub_mod64}" | openssl sha -sha256 -binary | urlbase64)"
#echo "thumbprint:" $thumbprint

# requests
# https://acme-staging.api.letsencrypt.org
# https://acme-v01.api.letsencrypt.org

# register account via private key
send_signed_request "https://acme-staging.api.letsencrypt.org/acme/new-reg" '{"resource": "new-reg", "contact": ["mailto: '$(catapult company.email)'"], "agreement": "'https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf'"}'
echo "response_status:" $response_status
echo "response:" $response

# request authorization for domain
if [ -f "/etc/ssl/certs/${domain}/keyauthorization" ]; then
    challenge_uri=$(<"/etc/ssl/certs/${domain}/challenge_uri")
    keyauthorization=$(<"/etc/ssl/certs/${domain}/keyauthorization")
else
    send_signed_request "https://acme-staging.api.letsencrypt.org/acme/new-authz" '{"resource": "new-authz", "identifier": {"type": "dns", "value": "'$(catapult websites.apache.$5.domain)'"}}'
    echo "response_status:" $response_status
    echo "response:" $response
    token=$(echo $response | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["challenges"][0]["token"]')
    challenge_uri=$(echo $response | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["challenges"][0]["uri"]')
    #echo "token:" $token
    keyauthorization="$token.$thumbprint"
    #echo "keyauthorization:" $keyauthorization
    mkdir --parents "/etc/ssl/certs/${domain}/token"
    echo -n "$keyauthorization" > "/etc/ssl/certs/${domain}/keyauthorization"
    ln -s "/etc/ssl/certs/${domain}/keyauthorization" "/etc/ssl/certs/${domain}/token/$token"
    echo -n "$challenge_uri" > "/etc/ssl/certs/${domain}/challenge_uri"
fi
#echo "challenge_uri:" $challenge_uri
#echo "keyauthorization:" $keyauthorization

# challenge the authorization
send_signed_request "${challenge_uri}" '{"resource": "challenge", "keyAuthorization": "'$keyauthorization'"}'
echo "response_status:" $response_status
echo "response:" $response

# get certificate
der=$(openssl req  -in "/etc/ssl/certs/${domain}/${domain}.csr" -outform DER | urlbase64)
send_signed_request "https://acme-staging.api.letsencrypt.org/acme/new-cert" '{"resource": "new-cert", "csr": "'$der'"}'
echo "response_status:" $response_status
echo "response:" $response

# convert certificate information into correct format and save to file.
CertData=$(echo $response | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["certificate"]')
if [ "$CertData" ] ; then
  echo -----BEGIN CERTIFICATE----- > "/etc/ssl/certs/${domain}/${domain}.crt"
  curl --silent "$CertData" | openssl base64 -e  >> "/etc/ssl/certs/${domain}/${domain}.crt"
  echo -----END CERTIFICATE-----  >> "/etc/ssl/certs/${domain}/${domain}.crt"
fi

# convert certificate information into correct format and save to file.
IssuerData=$(echo $response | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["issuer"]')
if [ "$IssuerData" ] ; then
  echo -----BEGIN CERTIFICATE----- > "/etc/ssl/certs/${domain}/chain.crt"
  curl --silent "$IssuerData" | openssl base64 -e  >> "/etc/ssl/certs/${domain}/chain.crt"
  echo -----END CERTIFICATE-----  >> "/etc/ssl/certs/${domain}/chain.crt"
fi

touch "/catapult/provisioners/redhat/logs/ssl_acme_letsencrypt.$(catapult websites.apache.$5.domain).complete"
