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

guard args.count == 3, let certPath = args.popLast(), let configPath = args.popLast() else {
    print("Please pass the paths to a digicert API key file and the certificate file you need to renew!")
    exit(1)
}

guard let digicertConfigData = Files.contents(atPath: configPath) else {
    print("Could not read your digicert config at \(configPath)")
    exit(1)
}

let digicertConfig: DigicertConfig
do {
    digicertConfig = try JSONDecoder().decode(DigicertConfig.self, from: digicertConfigData)
} catch {
    print("Error decoding Digicert Config at \(configPath):\n\(error)")
    print("Make sure it is JSON with two fields, \"key\" and \"organization\"")
    exit(1)
}

guard let certificate = Menkyo.readCertificateFile(certPath) else {
    print("Could not read certificate at \(certPath)")
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
    print("Certificate did not have a properly formatted Subject")
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


try runAndPrint(bash: "/usr/bin/git checkout -b certificate-\(filename)")

try runAndPrint(bash: "/usr/bin/git rm \(certPath)")
try runAndPrint(bash: "/usr/bin/git commit -a -m \"Replace certificate for \(filename)\"")

try runAndPrint(bash: certified)

try runAndPrint(bash: "/usr/bin/git add './etc/ssl/\(filename).cnf' './etc/ssl/\(filename).csr' './etc/ssl/private/\(filename).key'")
try runAndPrint(bash: "/usr/bin/git commit -a -m \"New key for \(commonName)\"")

guard let csrData = Files.contents(atPath: "./etc/ssl/\(filename).csr"), let csr = String(bytes: csrData, encoding: .utf8) else {
    print("Could not read the generated CSR ./etc/ssl/\(filename).csr")
    exit(1)
}

let digicert = DigicertSwift(apiKey: digicertConfig.key)
if let response = try digicert.requestCloud(commonName: commonName, sans: sans, csr: csr, organizationId: digicertConfig.organization)?.requests.first {
    print("Please visit the following URL to review and approve the request in state: \(response.status)")
    print("https://www.digicert.com/secure/requests/?status=pending#\(response.id)")
}

try runAndPrint(bash: "/usr/bin/git push origin certificate-\(filename)")
