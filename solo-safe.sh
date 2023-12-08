#!/usr/bin/env bash -e

APP_NAME='soloSafe'
APP_DESC='A simple TLS self-signed certificate and key generator.'
APP_VER='1.0.1'

# Argument Defaults
declare -a CRT_DNS_SANS
declare -a CRT_IP_SANS

# Defaults
WK_DEFAULT="./output"
SILENT=false
FORCE=false
PW_LENGTH=64
# Certificate Defaults
CRT_SUBJ=""
CRT_SANS=""
CRT_SIG_ALG='sha512'
CRT_ECC_CURVE='prime256v1'
CRT_DAYS=365
KEY_PW=""
CRT_SUBJ_CN='localhost.localdomain'
CRT_SUBJ_O=""
CRT_SUBJ_OU=""
CRT_SUBJ_C=""
CRT_SUBJ_ST=""
CRT_SUBJ_L=""
CRT_SUBJ_E=""
V3_REQ_OPTS=""
CREATE_PFX=false
PFX_EXPORT_PW=""
LH_DNS_SANS=("localhost" "localhost.localdomain")
LH_IP_SANS=("::1" "127.0.0.1")

# Load config defaults from a file if it exists
[[ -e "./${APP_NAME}.conf" ]] && source "./${APP_NAME}.conf"
[[ -e "~/.${APP_NAME}.conf" ]] && source "~/.${APP_NAME}.conf"

function is_unique() {
    ITEM=${1} # Value to add if it does not exist
    LIST=${2} # Existing list
    for san in ${LIST[@]}; do
        if [[ "${san}" == "${ITEM}" ]]; then
            return 1
        fi
    done
    return 0
}

function log_shell() {
    NC='\033[0m' # No Color
    RED='\033[0;31m'
    YLW='\033[1;33m'
    GRN='\033[0;32m'
    MSG="${1}"
    PREFIX=$(echo "${MSG}" | sed 's/[][]//g' | awk -F: '{print $1}')
    case "${PREFIX}" in
        INFO)
            MSG="${GRN}${MSG}${NC}"
            ;;
        WARN)
            MSG="${YLW}${MSG}${NC}"
            ;;
        ERROR)
            MSG="${RED}${MSG}${NC}"
            ;;
        *)
            MSG="${MSG}"
            ;;
    esac
    if ! ${SILENT}; then echo -e "${MSG}"; fi
}

function show_get_help() {
    local NC='\033[0m' # No Color
    local RED='\033[0;31m'
    local YLW='\033[1;33m'
    local GRN='\033[0;32m'
    local GRY='\033[0;37m'
    echo -e "${GRN}Usage: ${0} [-cn www.domain.com] [OPTIONS]\n"
      echo -e "${YLW}OPTIONS:${GRY}"
      echo "-env|--env-file - A file containing environment variables to load. Default: None"
      echo "-s|--silent - Don't output anything."
      echo "-f|--force - Overwrite existing files."
      echo "-o|--output-dir - The output directory. Default: ${WK_DEFAULT}"
      echo "-c|--curve - The ecc curve to use for the key. Default: ${CRT_ECC_CURVE}"
      echo "-a|--alg - The signature algorithm. Default: ${CRT_SIG_ALG}"
      echo "-d|--days - The number of days the certificate is valid. Default: ${CRT_DAYS}"
      echo -e "${YLW}Private Key Password: ${GRN}Use 'autogen:64' to generate a 64 character random password.${GRY}"
      echo "  -kp|--key-password - The password to use for the private key. Default: None (unencrypted)"
      echo -e "${YLW}PFX/PKCS12 Generation: ${GRN}Use 'autogen:64' to generate a 64 character random password.${GRY}"
      echo "  -pfx|--pfx '<export password>' - Create a PKCS12 file and specify the export password. Default: False"
      echo -e "${YLW}Subject Metadata options:${GRY}"
        echo "  -cn|--cn - The common name. Default: ${CRT_SUBJ_CN}"
        echo "  -org|--organization - The organization name. Default: ${CRT_SUBJ_O}"
        echo "  -ou|--organizational-unit - The organizational unit name. Default: ${CRT_SUBJ_OU}"
        echo "  -c|--country - The country name. Default: ${CRT_SUBJ_C}"
        echo "  -st|--state - The state name. Default: ${CRT_SUBJ_ST}"
        echo "  -ct|--locality|--city - The locality name. Default: ${CRT_SUBJ_L}"
        echo "  -e|--email - The email address. Default: ${CRT_SUBJ_E}"
      echo -e "${YLW}Subject Alternative Name options:${GRY}"
        echo "  -l|--localhost - Add all default localhost SANs."
        echo "  --san-dns - Add a DNS Subject Alternative Name. Multiple allowed."
        echo "  --san-ip - Add an IP Subject Alternative Name. Multiple allowed."
      echo -e "\n${GRN}EXAMPLE: ${0} -cn host.domain.com -san"
      echo -e "${NC}"
      exit 0
}

function generate_password() {
    # Generate a random key password
    length=${1:-64}
    echo $(openssl rand -base64 "$((length * 3 / 4))" | tr -d '/+=')
}

function verify_pw_length() {
    # Verify the password length is a number
    if [[ ! "${1}" =~ ^[0-9]+$ ]]; then
        log_shell "ERROR: Invalid key password length: \"${1}\". Must be a number."
        exit 1
    fi
    return 0
}

function parse_autogen() {
    # Convert an autogen password argument to a random password
    arg=${1}
    # Save the IFS value and set it to the delimiter
    CIFS=${IFS} && IFS=":"
    # Create an array by splitting the string
    read -ra split_array <<< "${1}"
    # Restore the IFS value
    IFS=${CIFS}
    length=${split_array[1]}
    # If the password length is not specified, use the default
    if [[ -z "${length}" ]]; then
        echo ${PW_LENGTH}
    fi
    # echo the length value
    echo ${length}
}

# Process passed arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -cn|--cn)
      CRT_SUBJ_CN="${2}"
      shift # past argument
      shift # past value
      ;;
    -org|--organization)
      CRT_SUBJ_O="${2}"
      shift # past argument
      shift # past value
      ;;
    -ou|--organizational-unit)
        CRT_SUBJ_OU="${2}"
        shift # past argument
        shift # past value
        ;;
    -c|--country)
        CRT_SUBJ_C="${2}"
        shift # past argument
        shift # past value
        ;;
    -st|--state)
        CRT_SUBJ_ST="${2}"
        shift # past argument
        shift # past value
        ;;
    -ct|--locality|--city)
        CRT_SUBJ_L="${2}"
        shift # past argument
        shift # past value
        ;;
    -e|--email)
        CRT_SUBJ_E="${2}"
        shift # past argument
        shift # past value
        ;;
    --san-dns)
      if $(is_unique "${2}" ${CRT_DNS_SANS}); then
        CRT_DNS_SANS+=("${2}")
      fi
      shift # past argument
      shift # past value
      ;;
    --san-ip)
      if $(is_unique "${2}" ${CRT_IP_SANS}); then
        CRT_IP_SANS+=("${2}")
      fi
      shift # past argument
      shift # past value
      ;;
    -l|--localhost)
      ## Add all default localhost SANs
      log_shell "INFO: Adding localhost SANs"
      for san in ${LH_DNS_SANS[@]}; do
          if $(is_unique "${san}" ${CRT_DNS_SANS}); then
            CRT_DNS_SANS+=("${san}")
          fi
      done
      for san in ${LH_IP_SANS[@]}; do
          if $(is_unique "${san}" ${CRT_IP_SANS}); then
            CRT_IP_SANS+=("${san}")
          fi
      done
      shift;
      ;;
    -ec|--curve)
      CRT_ECC_CURVE="${2}"
      shift # past argument
      shift # past value
      ;;
    -a|--alg)
      CRT_SIG_ALG="${2}"
      shift # past argument
      shift # past value
      ;;
    -d|--days)
      CRT_DAYS="${2}"
      shift # past argument
      shift # past value
      ;;
    -kp|--key-password)
      KEY_PW="${2}"
      if [[ ${KEY_PW} =~ 'autogen:' ]]; then
        log_shell "INFO: Generating random password for the private key"
        length=$(parse_autogen "${KEY_PW}")
        if verify_pw_length "${length}"; then
            KEY_PW=$(generate_password "${length}")
        fi
      fi
      shift # past argument
      shift # past value
      ;;
    -pfx|--pfx)
      CREATE_PFX=true
      PFX_EXPORT_PW="${2}"
      if [[ ${PFX_EXPORT_PW} =~ 'autogen:' ]]; then
        log_shell "INFO: Generating random password for the PFX export"
        length=$(parse_autogen "${PFX_EXPORT_PW}")
        if verify_pw_length "${length}"; then
            PFX_EXPORT_PW=$(generate_password "${length}")
        fi
      fi
      shift # past argument
      shift # past value
      ;;
    -o|--output-dir)
      WORKDIR="${2}"
      shift # past argument
      shift # past value
      ;;
    -env|--env-file)
      if [[ -e "${2}" ]]; then
        log_shell "[WARN]: Loading environment file. This may overwrite existing variables."
        source "${2}"
      fi
      shift # past argument
      shift # past value
      ;;
    -s|--silent)
      SILENT=true
      shift # past argument
      ;;
    -f|--force)
      FORCE=true
      shift # past argument
      ;;
    -h|--help)
      show_get_help
      ;;
    *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done

function init_workdir() {
  # Initialize the output dir or generate one
  [[ -d "${WK_DEFAULT}" ]] || mkdir -p "${WK_DEFAULT}"

  if [[ -z "${1}" ]]; then
    WORKDIR="${WK_DEFAULT}/$(echo ${CRT_SUBJ_CN} | sed 's/\*/wildcard/g')"
  else
    WORKDIR="${1}"
  fi
  [[ -d "${WORKDIR}" ]] || mkdir -p "${WORKDIR}"
  echo "${WORKDIR}"
}

function verify_cert_key() {
    # Set default values
    VERB=false
    CERT="${WORKDIR}/cert.pem}"
    KEY="${WORKDIR}/key.pem}"

    # Process passed arguments
    while [[ $# -gt 0 ]]; do
      key="$1"
      case $key in
        -c|--cert)
          CERT="${2}"
          shift # past argument
          shift # past value
          ;;
        -k|--key)
          KEY="${2}"
          shift # past argument
          shift # past value
          ;;
        -p|--password-file)
            KEY_PW_FILE="${2}"
            shift # past argument
            shift # past value
            ;;
        -v|--verbose)
          VERB=true
          shift # past argument
          ;;
        -h|--help)
          echo -e "Verify that a TLS certificate and key match.\n"
          echo -e "Usage ${0} -c cert.pem -k key.pem -v \n"
          echo "OPTIONS:"
          echo "-c|--cert - The private key file. default: \"${CERT}\""
          echo "-k|--key - The private key file. default: \"${KEY}\""
          echo "-v|--verbose - show the public keys for the cert and key."
          exit 0
          ;;
      esac
    done

    # Verify the files exist
    [[ ! -e "${CERT}" ]] && echo "[ERROR] Certificate file not found: \"${CERT}\"" && exit 1
    [[ ! -e "${KEY}" ]] && echo "[ERROR] Certificate file not found: \"${KEY}\"" && exit 1

    log_shell "INFO: Verifying certificate and key match"

    # Get the public key for the certificate
    certPubKey=$(openssl x509 -noout -pubkey -in "${CERT}")
    if ${VERB}; then
      echo "Certificate Public Key:"
      echo "${certPubKey}"
    fi
    # Get the public key from the private key
    if [[ -n "${KEY_PW_FILE}" ]]; then
        OPTS="-passin file:${KEY_PW_FILE}"
    fi
    keyPubKey=$(openssl pkey -pubout -in "${KEY}" ${OPTS})
    if ${VERB}; then
      echo "Private Key Public Key:"
      echo "${keyPubKey}"
    fi
    # Compare the public keys
    if [[ "${certPubKey}" == "${keyPubKey}" ]]; then
      log_shell "INFO: Passed - key and cert match"
      return 0
    else
      log_shell "ERROR: Failed - key and cert DO NOT match"
      return 1
    fi
}

# Set the working/output directory
WORKDIR=$(init_workdir "${WORKDIR}") && log_shell "INFO: Output Directory: ${WORKDIR}"

################################################################################
# Create a new array of formatted SANs
################################################################################
CRT_SANS="" # Initialize the SANs string
ct=0
for san in ${CRT_IP_SANS[@]}; do
    ((ct++))
    log_shell "INFO: Adding SAN: IP.${ct} = ${san}"
    CRT_SANS+="IP.${ct} = ${san}\n"
done

ct=0
for san in ${CRT_DNS_SANS[@]}; do
    ((ct++))
    log_shell "INFO: Adding SAN:  DNS.${ct} = ${san}"
    CRT_SANS+="DNS.${ct} = ${san}\n"
done

################################################################################
# Create the openssl config file
################################################################################
CONF_FILE="${WORKDIR}/openssl.conf"
MAKE_NEW=true
if [[ -e "${CONF_FILE}" ]] && ! ${FORCE}; then
  log_shell "ERROR: ${CONF_FILE} exists. Use -f|--force to overwrite."
  MAKE_NEW=${FORCE}
fi
if ! ${MAKE_NEW}; then
    log_shell "WARN: Using the existing openssl config file"
else
    log_shell "INFO: Creating new openssl config file"
    if [[ ${#CRT_SANS} -gt 0 ]]; then
        V3_REQ_OPTS="subjectAltName       = @alt_names"
    fi
cat <<- EOF > "${CONF_FILE}"
[ req ]
distinguished_name = req_distinguished_name
req_extensions     = v3_req
string_mask        = utf8only
prompt             = no

[ v3_req ]
nsComment            = "Created By: ${APP_NAME} v${APP_VER}"
keyUsage             = keyEncipherment, dataEncipherment
extendedKeyUsage     = serverAuth
${V3_REQ_OPTS}

[req_distinguished_name]
commonName = "${CRT_SUBJ_CN}"
EOF
    [[ -n "${CRT_SUBJ_E}" ]] && echo "emailAddress = \"${CRT_SUBJ_E}\"" >> "${CONF_FILE}"
    [[ -n "${CRT_SUBJ_C}" ]] && echo "countryName = \"${CRT_SUBJ_C}\"" >> "${CONF_FILE}"
    [[ -n "${CRT_SUBJ_ST}" ]] && echo "stateOrProvinceName = \"${CRT_SUBJ_ST}\"" >> "${CONF_FILE}"
    [[ -n "${CRT_SUBJ_L}" ]] && echo "localityName = \"${CRT_SUBJ_L}\"" >> "${CONF_FILE}"
    [[ -n "${CRT_SUBJ_O}" ]] && echo "0.organizationName = \"${CRT_SUBJ_O}\"" >> "${CONF_FILE}"
    [[ -n "${CRT_SUBJ_OU}" ]] && echo "organizationalUnitName = \"${CRT_SUBJ_OU}\"" >> "${CONF_FILE}"

    if [[ -n "${CRT_SANS}" ]]; then
        echo -e "\n[alt_names]" >> "${CONF_FILE}"
        echo -e "${CRT_SANS}" >> "${CONF_FILE}"
    fi
fi

################################################################################
# Create the private key file
################################################################################
KEY_FILE="${WORKDIR}/key.pem"
MAKE_NEW=true
if [[ -e "${KEY_FILE}" ]] && ! ${FORCE}; then
  log_shell "ERROR: ${KEY_FILE} exists. Use -f|--force to overwrite."
  MAKE_NEW=${FORCE}
fi
if ! ${MAKE_NEW}; then
    log_shell "WARN: Using the existing private key file"
else
    if [[ -z "${KEY_PW}" ]]; then
        log_shell "INFO: Creating new unencrypted private key"
        openssl ecparam -name ${CRT_ECC_CURVE} -genkey -noout -outform PEM -out "${KEY_FILE}"
    else
        log_shell "INFO: Creating new encrypted private key"
        echo -n "${KEY_PW}" > "${KEY_FILE}.pw" && chmod 600 "${KEY_FILE}.pw"
        openssl ecparam -name ${CRT_ECC_CURVE} -out "${WORKDIR}/ecparam.pem"
        openssl genpkey -paramfile "${WORKDIR}/ecparam.pem" -aes-128-cbc -pass file:"${KEY_FILE}.pw" -out "${KEY_FILE}"
        rm -f "${WORKDIR}/ecparam.pem"
    fi
fi

################################################################################
# Create the certificate
################################################################################
CRT_FILE="${WORKDIR}/cert.pem"
PFX_FILE="${WORKDIR}/cert.pfx"
MAKE_NEW=true
if [[ -e "${CRT_FILE}" ]] && ! ${FORCE}; then
  log_shell "ERROR: ${CRT_FILE} exists. Use -f|--force to overwrite."
  MAKE_NEW=${FORCE}
fi
if ! ${MAKE_NEW}; then
    log_shell "WARN: Preserving the existing certificate file"
else

    if [[ -n "${KEY_PW}" ]]; then
        ARGS="-passin file:${KEY_FILE}.pw "
    fi
    log_shell "INFO: Creating new TLS certificate"
    openssl req -new -x509 -${CRT_SIG_ALG} -nodes ${ARGS} \
        -config "${CONF_FILE}" \
        -key "${KEY_FILE}" \
        -out "${CRT_FILE}" \
        -days ${CRT_DAYS}  \
        -extensions 'v3_req'

    if [[ ${?} -eq 0 ]]; then
      if ! ${SILENT}; then
          echo "###########################################################"
          openssl x509  -noout -in "${CRT_FILE}" -text \
            -certopt no_header,no_version,no_signame,no_issuer,no_pubkey,no_aux
          echo "###########################################################"
      fi
      log_shell "INFO: Certificate created successfully."
      log_shell "INFO: Certificate: ${CRT_FILE}"

      log_shell "INFO: Private Key: ${KEY_FILE}"
      if ${CREATE_PFX}; then
          echo -n "${PFX_EXPORT_PW}" > "${PFX_FILE}.pw" && chmod 600 "${PFX_FILE}.pw"
          openssl pkcs12 -aes256 -export -keyex ${ARGS} \
           -in "${CRT_FILE}" \
           -inkey "${KEY_FILE}" \
           -out "${PFX_FILE}" \
           -password file:"${PFX_FILE}.pw"
          log_shell "INFO: PFX File: ${PFX_FILE}"
      fi
    else
      log_shell "ERROR: Certificate creation failed."
    fi
fi

################################################################################
# Verify the certificate and key
################################################################################
#if ! $SILENT; then OPTS='-v' ;fi
if [[ -n "${KEY_FILE}.pw" ]] && [[ -n "${KEY_FILE}" ]]; then
    OPTS="${OPTS} -p ${KEY_FILE}.pw"
fi

if [[ $(verify_cert_key -c "${CRT_FILE}" -k "${KEY_FILE}" ${OPTS}) ]]; then
    exit 0
else
    exit 1
fi



