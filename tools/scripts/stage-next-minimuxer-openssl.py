#!/usr/bin/env python3
"""Unify OpenSSL in isolated, pinned dependency checkouts before app migration."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
dependency = '.package(url: "https://github.com/krzyzanowskim/OpenSSL.git", exact: "3.6.2000")'
product = '.product(name: "OpenSSL", package: "OpenSSL")'

def replace(text, before, after):
    if after and before in after and after in text:
        return text
    if before not in text and (not after or after in text):
        return text
    if text.count(before) != 1:
        raise SystemExit(f"Expected exactly one manifest declaration: {before}")
    return text.replace(before, after)

alt = root / 'altsign/Package.swift'
text = alt.read_text()
text = replace(text, '"ldid", "ldid-core", "OpenSSL"]', '"ldid", "ldid-core"]')
text = replace(text, 'dependencies: [\n//', 'dependencies: [\n        ' + dependency + ',\n//')
pattern = r'\s*// exposing OpenSSL as target\s*\.binaryTarget\(\s*name: "OpenSSL",\s*path: "Dependencies/OpenSSL.xcframework"\s*\),'
text, count = re.subn(pattern, '', text)
if count != 1 and '.binaryTarget(' in text:
    raise SystemExit('Unexpected AltSign binary target')
# Give each source consumer a direct package dependency rather than relying on
# a product-wide framework search path to expose OpenSSL headers.
text = replace(text, 'dependencies: ["ldid-core"]', 'dependencies: ["ldid-core", ' + product + ']')
text = replace(text, 'name: "CCoreCrypto",\n\t\t\tpath:', 'name: "CCoreCrypto",\n            dependencies: [' + product + '],\n\t\t\tpath:')
text = replace(text, '"CoreCrypto",\n\t\t\t\t"ldid",', '"CoreCrypto",\n\t\t\t\t"ldid",\n                ' + product + ',')
alt.write_text(text)

# The retained parser leaves output pointers uninitialized on malformed input.
# Guard the parse result and release its allocations in the staged candidate.
certificate = root / 'altsign/AltSign/Model/Apple API/ALTCertificate.m'
text = certificate.read_text()
text = replace(text,
    'BIO *inputP12Buffer = BIO_new_mem_buf((const void *)p12Data.bytes, (int)p12Data.length);',
    'BIO *inputP12Buffer = BIO_new_mem_buf((const void *)p12Data.bytes, (int)p12Data.length);\n'
    '    if (inputP12Buffer == NULL) { return nil; }')
text = replace(text, 'BIO_free(inputP12Buffer);',
    'BIO_free(inputP12Buffer);\n    if (inputP12 == NULL) { return nil; }')
text = replace(text,
    'EVP_PKEY *key;\n    X509 *certificate;\n    PKCS12_parse(inputP12, password.UTF8String, &key, &certificate, NULL);\n\n'
    '    if (key == nil || certificate == nil)\n    {\n        return nil;\n    }',
    'EVP_PKEY *key = NULL;\n    X509 *certificate = NULL;\n'
    '    int parsed = PKCS12_parse(inputP12, password.UTF8String, &key, &certificate, NULL);\n'
    '    PKCS12_free(inputP12);\n'
    '    if (parsed != 1 || key == NULL || certificate == NULL)\n    {\n'
    '        EVP_PKEY_free(key);\n        X509_free(certificate);\n        return nil;\n    }')
text = replace(text, 'BIO_free(privateKeyBuffer);\n\n    return self;',
    'BIO_free(privateKeyBuffer);\n    EVP_PKEY_free(key);\n    X509_free(certificate);\n\n    return self;')
certificate.write_text(text)

remote = root / 'remotepairingkit/Package.swift'
text = remote.read_text()
text = replace(text, ',\n        .library(\n            name: "OpenSSL",\n            targets: ["OpenSSL"]\n        )', '')
text = replace(text, 'dependencies: []', 'dependencies: [' + dependency + ']')
pattern = r'\s*\.binaryTarget\(\s*name: "OpenSSL",\s*url: "[^"\n]+",\s*checksum: "[0-9a-f]+"\s*\),'
text, count = re.subn(pattern, '', text)
if count != 1 and '.binaryTarget(' in text:
    raise SystemExit('Unexpected RemotePairingKit binary target')
text = replace(text, '.target(name: "OpenSSL")', product)
remote.write_text(text)

gateway = root / 'minimuxer/DeviceGateway/Package.swift'
text = gateway.read_text()
text = replace(text, '.package(url: "https://github.com/mahee96/RemotePairingKit.git", revision: "e3f70d16c0c551540a533a39d540e78e5b0a60a8")', '.package(path: "../../remotepairingkit"),\n        ' + dependency)
text = replace(text, '.product(name: "OpenSSL",   package: "RemotePairingKit")', product)
gateway.write_text(text)
