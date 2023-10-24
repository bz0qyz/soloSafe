# tls-ssgen
Self-signed TLS Certificate Generator for openssl

## Usage
`bash tls-ssgen.sh -cn <common name> [ <OPTIONS> ]`

### OPTIONS
  - `-env|--env-file <path_to_file>`: A file containing environment variables to load. Default: None. If using a ENV file, use it as the first argument so later arguments are not overridden.
  - `-s|--silent`: Don't output anything.
  - `-f|--force` - Overwrite existing files.
  - `-o|--output-dir <path_to_directory>`: The output directory. Default: ./output
  - `-c|--curve <curve>`: The ecc curve to use for the key. Default: prime256v1. Get available curves: `openssl ecparam -list_curves`.
  - `-a|--alg`: The signature algorithm. Default: sha512
  - `-d|--days <days>`: The number of days the certificate is valid. Default: `3650`
  - `-kp|--key-password '<password>'`: The password to use for the private key. Default: None (unencrypted).
  - `-pfx|--pfx '<export password>'`: Create a PKCS12 file and specify the export password. Default: False
  - Subject Metadata Options:
    - `-cn|--cn <hostname.domain>`: The common name. Default: localhost.localdomain
    - `-org|--organization` <org_name>: The organization name. Default: None
    - `-ou|--organizational-unit <ou_name>`: The organizational unit name. Default: None
    - `-c|--country <country code>`: The country name. Default: None
    - `-st|--state` <full_state_name>: The state name. Default: None
    - `-ct|--locality|--city <city name>`: The locality name. Default: None
    - `-e|--email <email_address>`: The email address. Default: None
  - Subject Alternative Name options (can be specified multiple times):
    - `-l|--localhost`: Add all default localhost SANs.
    - `--san-dns <hostname.domain>`: Add a DNS Subject Alternative Name.
    - `--san-ip <IP Address>`: Add an IP Subject Alternative Name.

#### Environment File
You can optionally provide a configuration file with the options specified as environment variables.
The file should be in the format of `KEY=VALUE` with each option on a new line. See the example file: `tls-ssgen.conf`
Default environment files will be loaded if the exist in the following order:
- `./tls-ssgen.conf`
- `~/.tls-ssgen.conf`
