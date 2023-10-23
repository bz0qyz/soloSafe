#!/usr/bin/env bash -e
# Argument Defaults
declare -a CRT_DNS_SANS
declare -a CRT_IP_SANS

# Defaults
WK_DEFAULT="./output"
SILENT=false
FORCE=false
# Certificate Defaults
CRT_SUBJ=""
CRT_SANS=""
CRT_SIG_ALG='sha512'
CRT_ECC_CURVE='prime256v1'
CRT_DAYS=365
CRT_SUBJ_CN='localhost.localdomain'
CRT_SUBJ_O=""
CRT_SUBJ_OU=""
CRT_SUBJ_C=""
CRT_SUBJ_ST=""
CRT_SUBJ_L=""
CRT_SUBJ_E=""
V3_REQ_OPTS=""
CREATE_PFX=false
LH_DNS_SANS=("localhost" "localhost.localdomain" "lvh.me")
LH_IP_SANS=("::1" "127.0.0.1")

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
    if ! ${SILENT}; then echo -e "${1}"; fi
}

# Process passed arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
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
    -l|--localhost)
      ## Add all default localhost SANs
      for san in ${LH_DNS_SANS[@]}; do
          if [[ $(is_unique "${san}" ${CRT_DNS_SANS}) ]]; then
            CRT_DNS_SANS+=("${san}")
          fi
      done
      for san in ${LH_IP_SANS[@]}; do
          if [[ $(is_unique "${san}" ${CRT_IP_SANS}) ]]; then
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
    -o|--output-dir)
      WORKDIR="${2}"
      shift # past argument
      shift # past value
      ;;
    -pfx|--pfx)
      CREATE_PFX=true
      shift # past argument
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
      echo -e "Usage ${0} [-cn www.domain.com][-a <sig algorithm> -c <curve>]\n"
      echo "-c|--curve - The ecc curve to use for the key. Default: ${CRT_ECC_CURVE}"
      echo "-a|--alg - The signature algorithm. Default: ${CRT_SIG_ALG}"
      echo "-d|--days - The number of days the certificate is valid. Default: ${CRT_DAYS}"
      echo "-o|--output-dir - The output directory. Default: ${WK_DEFAULT}"
      echo "-pfx|--pfx - Create a PKCS12 file. Default: False"
      echo "-s|--silent - Don't output anything."
      echo "-f|--force - Overwrite existing files."
      echo "Subject Metadata options:"
        echo "  -cn|--cn - The common name. Default: ${CRT_SUBJ_CN}"
        echo "  -org|--organization - The organization name. Default: ${CRT_SUBJ_O}"
        echo "  -ou|--organizational-unit - The organizational unit name. Default: ${CRT_SUBJ_OU}"
        echo "  -c|--country - The country name. Default: ${CRT_SUBJ_C}"
        echo "  -st|--state - The state name. Default: ${CRT_SUBJ_ST}"
        echo "  -ct|--locality|--city - The locality name. Default: ${CRT_SUBJ_L}"
        echo "  -e|--email - The email address. Default: ${CRT_SUBJ_E}"
      echo "Subject Alternative Name options:"
        echo "  -l|--localhost - Add all default localhost SANs."
        echo "  --san-dns - Add a DNS Subject Alternative Name. Multiple allowed."
        echo "  --san-ip - Add an IP Subject Alternative Name. Multiple allowed."
      echo -e "\nEXAMPLE: ${0} -cn host.domain.com -san"
      exit 0
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
    WORKDIR="${WK_DEFAULT}/${CRT_SUBJ_CN}"
  else
    WORKDIR="${1}"
  fi
  [[ -d "${WORKDIR}" ]] || mkdir -p "${WORKDIR}"
  echo "${WORKDIR}"
}

WORKDIR=$(init_workdir "${WORKDIR}")
log_shell "INFO: Output Directory: ${WORKDIR}"

# Create a new array of formatted SANs
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

# Create the openssl config file
CONF_FILE="${WORKDIR}/openssl.conf"
MAKE_NEW=true
if [[ -e "${CONF_FILE}" ]] && ! ${FORCE}; then
  log_shell "ERROR: ${CONF_FILE} exists. Use -f|--force to overwrite."
  MAKE_NEW=${FORCE}
fi
if ! ${MAKE_NEW}; then
    log_shell "INFO: Using the existing openssl config file"
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
nsComment            = "Created By: $(basename ${0})"
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

# Create the private key file
KEY_FILE="${WORKDIR}/key.pem"
MAKE_NEW=true
if [[ -e "${KEY_FILE}" ]] && ! ${FORCE}; then
  log_shell "ERROR: ${KEY_FILE} exists. Use -f|--force to overwrite."
  MAKE_NEW=${FORCE}
fi
if ! ${MAKE_NEW}; then
    log_shell "INFO: Using the existing private key file"
else
    log_shell "INFO: Creating new private key"
    openssl ecparam -name ${CRT_ECC_CURVE} -genkey -noout -outform PEM -out "${KEY_FILE}"
fi

# Create the certificate
CRT_FILE="${WORKDIR}/cert.pem"
PFX_FILE="${WORKDIR}/cert.pfx"
openssl req -new -x509 -${CRT_SIG_ALG} -nodes \
    -config "${CONF_FILE}" \
    -key "${KEY_FILE}" \
    -out "${CRT_FILE}" \
    -days ${CRT_DAYS}  \
    -extensions 'v3_req'

if [[ ${?} -eq 0 ]]; then
  if ! ${SILENT}; then  openssl x509 -text -noout -in "${CRT_FILE}"; fi
  log_shell "INFO: Certificate created successfully."
  log_shell "INFO: Certificate: ${CRT_FILE}"
  log_shell "INFO: Private Key: ${KEY_FILE}"
  if ${CREATE_PFX}; then
      openssl pkcs12 -aes256 -export -keyex \
       -in "${CRT_FILE}" \
       -inkey "${KEY_FILE}" \
       -out "${PFX_FILE}"
      log_shell "INFO: PFX File: ${PFX_FILE}"
  fi
else
  log_shell "ERROR: Certificate creation failed."
fi

exit 0

