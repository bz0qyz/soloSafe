#!/usr/bin/env zsh
# Argument Defaults
declare -A CRT
declare -A CRT_SUBJ
declare -a CRT_DNS_SANS
declare -a CRT_IP_SANS
CRT[SIG_ALG]='sha512'
CRT[ECC_CURVE]='prime256v1'
CRT[DAYS]=365
CRT_SUBJ[CN]='localhost.localdomain'
LH_DNS_SANS=("localhost", "localhost.localdomain", "localhost4.localdomain4"  "lvh.me")
LH_IP_SANS=("127.0.0.1")

function add_if_not_exists() {
    ITEM=${1} # Value to add if it does not exist
    LIST=${2} # Existing list
    echo "checking ${1} in ${2[@]}"
    if ((! $LIST[(Ie)$ITEM])); then
        echo "Adding ${ITEM} to list"
        LIST+=("${ITEM}")
    fi

}

# Process passed arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -cn|--cn)
      CRT_SUBJ[CN]="${2}"
      shift # past argument
      shift # past value
      ;;
    --san-dns)
      add_if_not_exists "${2}" ${CRT_DNS_SANS}
      shift # past argument
      shift # past value
      ;;
    --san-ip)
      add_if_not_exists "${2}" ${CRT_IP_SANS}
      shift # past argument
      shift # past value
      ;;
    -l|--localhost)
      ## Add all default localhost SANs
      for san in ${LH_DNS_SANS[@]}; do
          add_if_not_exists "${san}" ${CRT_DNS_SANS}
      done
      for san in ${LH_IP_SANS[@]}; do
          add_if_not_exists "${san}" ${CRT_IP_SANS}
      done
      shift;
      ;;
    -c|--curve)
      CRT[ECC_CURVE]="${2}"
      shift # past argument
      shift # past value
      ;;
    -a|--alg)
      CRT[SIG_ALG]="${2}"
      shift # past argument
      shift # past value
      ;;
    -d|--days)
      CRT[DAYS]="${2}"
      shift # past argument
      shift # past value
      ;;
    -h|--help)
      echo -e "Usage ${0} [-cn www.domain.com][-a <sig algorithm> -c <curve>]\n"
      echo "-c|--curve - The ENV Variable prefix (without trailing underscores)"
      echo "-a|--alg - The signature algorithm. Default: ${SIG_ALG}"
      echo -e "\nEXAMPLE: ${0} -cn host.domain.com -san"
      exit 0
      ;;
    *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done

WORKDIR=$(mktemp -d -p '/tmp' -t 'openssl_')
echo ${WORKDIR}
for san in ${CRT_DNS_SANS[@]}; do
    echo "SAN: ${san}"
done

for san in ${CRT_DNS_SANS[@]}; do
    echo "SAN: ${san}"
done

rm -rf ${WORKDIR}
exit 0


#openssl req -new -x509 -sha512 \
#    -key key.pem -nodes \
#    -out cert.pem \
#    -config openssl.conf \
#    -days 365  \
#    -extensions 'v3_req' \
#    -subj "/CN=host.revealdata.com/emailAddress=username@revealdata.com/O=Reveal Data/OU=Operations/C=US/ST=Illinois/L=Chicago"
#
#openssl req -new -sha512 \
#    -key key.pem -nodes \
#    -out cert.csr \
#    -config openssl.conf \
#    -days 365  \
#    -subj "/CN=host.revealdata.com/emailAddress=username@revealdata.com/O=Reveal Data/OU=Operations/C=US/ST=Illinois/L=Chicago"
