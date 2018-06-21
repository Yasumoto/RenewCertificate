# RenewCertificate

Tool to update a certificate and automatically submit a request to Digicert's API.

Hopefully this prevents any expired certs 🔏

This depends on [`certified`](https://github.com/rcrowley/certified) and a particular
file system structure to work.

## Usage

```sh
$ cat /path/to/digicert_config.json
{
    "key": "API Key for DigiCert",
    "organization": 12345
}
$ RenewCertificate /path/to/digicert_config.json /path/to/expiring/certificate_file.crt
```
