#!/usr/bin/env python3

import ipaddress
import json
import re
from argparse import ArgumentParser, Namespace
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from subprocess import check_call, check_output
from typing import Any, Dict, Optional

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

CA_VALIDITY_DAYS = 3650
CLIENT_VALIDITY_DAYS = 365

CA_KEY_FIELD = "frpCaKey"
CA_CERT_FIELD = "frpCaCert"
SERVER_KEY_FIELD = "frpServerKey"
SERVER_CERT_FIELD = "frpServerCert"
CLIENT_KEY_FIELD = "frpClientKey"
CLIENT_CERT_FIELD = "frpClientCert"

SERVER_CN = "external.iverian.ru"
CLIENT_CN = "home.iverian.ru"


def main():
    args = arguments()

    if args.force:
        ca = CA.create()
        server = Certificate.create(ca, SERVER_CN)
        client = Certificate.create(ca, CLIENT_CN)
    else:
        secrets = sops_read()
        ca = CA.read_or_create(secrets.get(CA_KEY_FIELD), secrets.get(CA_CERT_FIELD))
        server = Certificate.read_or_create(
            ca,
            SERVER_CN,
            secrets.get(SERVER_KEY_FIELD),
            secrets.get(SERVER_CERT_FIELD),
        )
        client = Certificate.read_or_create(
            ca,
            CLIENT_CN,
            secrets.get(CLIENT_KEY_FIELD),
            secrets.get(CLIENT_CERT_FIELD),
        )

    ca_cert, ca_key = ca.pem()
    server_cert, server_key = server.pem()
    client_cert, client_key = client.pem()

    sops_set(CA_CERT_FIELD, ca_cert)
    sops_set(CA_KEY_FIELD, ca_key)
    sops_set(SERVER_CERT_FIELD, server_cert)
    sops_set(SERVER_KEY_FIELD, server_key)
    sops_set(CLIENT_CERT_FIELD, client_cert)
    sops_set(CLIENT_KEY_FIELD, client_key)


def arguments() -> Namespace:
    args = ArgumentParser("cert")
    args.add_argument("-f", "--force", action="store_true")
    return args.parse_args()


@dataclass
class CA:
    cert: x509.Certificate
    key: rsa.RSAPrivateKey

    def pem(self) -> tuple[str, str]:
        return (
            self.cert.public_bytes(serialization.Encoding.PEM).decode(),
            self.key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            ).decode(),
        )

    @staticmethod
    def read_or_create(key_pem: Optional[str], cert_pem: Optional[str]) -> CA:
        ca = CA.read(key_pem, cert_pem)
        if not ca:
            print("# Creating new CA key")
            ca = CA.create()
        return ca

    @staticmethod
    def read(key_pem: Optional[str], cert_pem: Optional[str]) -> Optional[CA]:
        if not key_pem or not cert_pem:
            return None

        key = serialization.load_pem_private_key(key_pem.encode(), password=None)
        assert isinstance(key, rsa.RSAPrivateKey)
        cert = x509.load_pem_x509_certificate(cert_pem.encode())
        return CA(cert=cert, key=key)

    @staticmethod
    def create() -> CA:
        ca_key = create_private_key()
        ca_subject = build_subject()
        now = datetime.now(timezone.utc)

        ca_cert = (
            x509.CertificateBuilder()
            .subject_name(ca_subject)
            .issuer_name(ca_subject)
            .public_key(ca_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=1))
            .not_valid_after(now + timedelta(days=CA_VALIDITY_DAYS))
            .add_extension(
                x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()),
                critical=False,
            )
            .add_extension(
                x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()),
                critical=False,
            )
            .add_extension(
                x509.BasicConstraints(ca=True, path_length=None), critical=True
            )
            .add_extension(
                x509.KeyUsage(
                    digital_signature=False,
                    content_commitment=False,
                    key_encipherment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    key_cert_sign=True,
                    crl_sign=True,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
            .sign(private_key=ca_key, algorithm=hashes.SHA256())
        )

        return CA(cert=ca_cert, key=ca_key)


@dataclass
class Certificate:
    cert: x509.Certificate
    key: rsa.RSAPrivateKey

    def pem(self) -> tuple[str, str]:
        return (
            self.cert.public_bytes(serialization.Encoding.PEM).decode(),
            self.key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            ).decode(),
        )

    @staticmethod
    def read_or_create(
        ca: CA,
        client_cn: str,
        key_pem: Optional[str],
        cert_pem: Optional[str],
    ) -> Certificate:
        result = Certificate.read(key_pem, cert_pem)
        if not result:
            print(f"# Creating new Certificate for {client_cn}")
            result = Certificate.create(ca, client_cn)
        return result

    @staticmethod
    def read(key_pem: Optional[str], cert_pem: Optional[str]) -> Optional[Certificate]:
        if not key_pem or not cert_pem:
            return None

        key = serialization.load_pem_private_key(key_pem.encode(), password=None)
        assert isinstance(key, rsa.RSAPrivateKey)
        cert = x509.load_pem_x509_certificate(cert_pem.encode())
        return Certificate(cert=cert, key=key)

    @staticmethod
    def create(ca: CA, client_cn: str) -> Certificate:
        client_key = create_private_key()
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, client_cn)])
        now = datetime.now(timezone.utc)

        builder = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(ca.cert.subject)
            .public_key(client_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=1))
            .not_valid_after(now + timedelta(days=CLIENT_VALIDITY_DAYS))
            .add_extension(
                x509.BasicConstraints(ca=False, path_length=None), critical=True
            )
            .add_extension(
                x509.SubjectKeyIdentifier.from_public_key(client_key.public_key()),
                critical=False,
            )
            .add_extension(
                x509.AuthorityKeyIdentifier.from_issuer_public_key(ca.key.public_key()),
                critical=False,
            )
            .add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    content_commitment=False,
                    key_encipherment=True,
                    data_encipherment=False,
                    key_agreement=False,
                    key_cert_sign=False,
                    crl_sign=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
            .add_extension(
                x509.ExtendedKeyUsage(
                    [ExtendedKeyUsageOID.CLIENT_AUTH, ExtendedKeyUsageOID.SERVER_AUTH]
                ),
                critical=False,
            )
        )

        san_extension = build_subject_alternative_name(client_cn)
        if san_extension is not None:
            builder = builder.add_extension(san_extension, critical=False)

        client_cert = builder.sign(private_key=ca.key, algorithm=hashes.SHA256())

        return Certificate(client_cert, client_key)


def build_output_stem(common_name: str) -> str:
    sanitized = re.sub(r"[^A-Za-z0-9._-]+", "_", common_name.strip()).strip("._-")
    if not sanitized:
        raise ValueError(
            "Common Name must contain at least one safe filename character."
        )
    return sanitized


def build_subject_alternative_name(
    common_name: str,
) -> x509.SubjectAlternativeName | None:
    try:
        ip_value = ipaddress.ip_address(common_name)
        return x509.SubjectAlternativeName([x509.IPAddress(ip_value)])
    except ValueError:
        pass

    if "@" in common_name:
        return x509.SubjectAlternativeName([x509.RFC822Name(common_name)])

    if re.fullmatch(r"[A-Za-z0-9.-]+", common_name):
        return x509.SubjectAlternativeName([x509.DNSName(common_name)])

    return None


def create_private_key() -> rsa.RSAPrivateKey:
    return rsa.generate_private_key(public_exponent=65537, key_size=4096)


def build_subject() -> x509.Name:
    values = [
        (NameOID.COUNTRY_NAME, prompt_value("Country Name (2 letter code)", "XX")),
        (
            NameOID.STATE_OR_PROVINCE_NAME,
            prompt_value("State or Province Name (full name)"),
        ),
        (
            NameOID.LOCALITY_NAME,
            prompt_value("Locality Name (eg, city)", "Default City"),
        ),
        (
            NameOID.ORGANIZATION_NAME,
            prompt_value("Organization Name (eg, company)", "Default Company Ltd"),
        ),
        (
            NameOID.ORGANIZATIONAL_UNIT_NAME,
            prompt_value("Organizational Unit Name (eg, section)"),
        ),
        (
            NameOID.COMMON_NAME,
            prompt_required("Common Name (eg, your name or your server's hostname)"),
        ),
        (NameOID.EMAIL_ADDRESS, prompt_value("Email Address")),
    ]

    attributes = []
    for oid, value in values:
        value = value.strip()
        if value:
            if oid == NameOID.COUNTRY_NAME and len(value) != 2:
                raise ValueError("Country Name must be a 2 letter code.")
            attributes.append(x509.NameAttribute(oid, value))
    return x509.Name(attributes)


def prompt_value(label: str, default: str = "") -> str:
    value = input(f"{label} [{default}]: ").strip()
    return value or default


def prompt_required(label: str) -> str:
    while True:
        value = input(f"{label}: ").strip()
        if value:
            return value
        print("Please provide a non-empty value.")


def sops_read(
    file: Optional[Path] = None,
) -> Dict[str, Any]:
    file = (file or Path("main.sops.yaml")).resolve()

    out = json.loads(
        check_output(
            ["sops", "decrypt", "--output-type", "json", str(file)],
            encoding="utf-8",
        )
    )
    assert isinstance(out, dict)
    return out


def sops_set(
    key: str,
    value: Any,
    file: Optional[Path] = None,
):
    file = (file or Path("main.sops.yaml")).resolve()
    check_call(["sops", "set", str(file), f'["{str(key)}"]', json.dumps(value)])


if __name__ == "__main__":
    main()
