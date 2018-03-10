import Foundation

import DigicertSwift
import Menkyo
import SwiftShell

struct DigicertConfig: Codable {
    let key: String
    let organization: Int
}

var args = CommandLine.arguments

if (args.contains("--help") || args.contains("-h")) {
    print("RenewCertificate <keyfile> <path>.crt")
    print("Built from https://github.com/Yasumoto/RenewCertificate")
    exit(1)
}

guard args.count == 3, let path = args.popLast(), let keyFile = args.popLast() else {
    print("Please pass the paths to a digicert API key file and the certificate file you need to renew!")
    exit(1)
}

guard let digicertKeyData = Files.contents(atPath: path) else {
    print("Could not read your digicert config at \(path)")
    print("Make sure it is JSON with two fields, \"key\" and \"organization\"")
    exit(1)
}

let digicertConfig = try JSONDecoder().decode(DigicertConfig.self, from: digicertKeyData)

guard let certificate = Menkyo.readCertificateFile(path) else {
    print("Could not read certificate at \(path)")
    exit(1)
}

guard let commonName = certificate.subjectName?[.commonName] else {
    print("Certificate did not have a common name! This should be provided to identify the cert.")
    exit(1)
}

guard let sans = certificate.alternateNames else {
    print("Certificate did not have any SANs! These are now required.")
    exit(1)
}

guard let country = certificate.subjectName?[.country],
    let state = certificate.subjectName?[.state],
    let locality = certificate.subjectName?[.locality],
    let organization = certificate.subjectName?[.organization] else {
    print("Certificate did not have properly formatted Subject")
    exit(1)
}

var certified = "/usr/bin/certified --no-sign C=\"\(country)\" ST=\"\(state)\" L=\"\(locality)\" O=\"\(organization)\" CN=\"\(commonName)\""

var filename = commonName
if commonName.starts(with: "*") {
    filename = commonName.replacingOccurrences(of: "*", with: "wildcard")
    certified.append(" --name \(filename)")
}

for san in sans {
    certified.append(" +\"\(san)\"")
}

print("Running: \(certified)")

try runAndPrint(bash: certified)
try runAndPrint(bash: "/usr/bin/git add './etc/ssl/\(filename).cnf' './etc/ssl/\(filename).csr' './etc/ssl/private/\(filename).key'")
try runAndPrint(bash: "/usr/bin/git commit -a -m \"New key for \(commonName)\"")

guard let csrData = Files.contents(atPath: "./etc/ssl/\(filename).csr"), let csr = String(bytes: csrData, encoding: .utf16) else {
    print("Could not read the generated CSR ./etc/ssl/\(filename).csr")
    exit(1)
}

let digicert = DigicertSwift(apiKey: digicertConfig.key)
if let response = try digicert.requestWildcard(commonName: commonName, csr: csr, organizationId: digicertConfig.organization) {
    print("Response from Digicert: \(response)")
}
