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

guard args.count == 3, let certLocation = args.popLast(), let configLocation = args.popLast() else {
    print("Please pass the paths to a digicert API key file and the certificate file you need to renew!")
    exit(1)
}

let manager = FileManager.default
guard let configPath = URL(string: configLocation)?.absoluteString, manager.fileExists(atPath: configPath) else {
    print("Please make sure a json file with credentials exists at \(configLocation)")
    exit(1)
}
guard let certPath = URL(string: certLocation)?.absoluteString, manager.fileExists(atPath: certPath) else {
    print("Please make sure a certificate file exists at \(certLocation)")
    exit(1)
}

var prefixBranch = false
let prefix = URL(string: certPath)!.pathComponents
    .filter({ path in
        if prefixBranch {
            return false
        }
        if path == "default" {
            prefixBranch = true
        }
        return true
    })
    .joined(separator: "/")

guard let digicertConfigData = manager.contents(atPath: configPath) else {
    print("Could not read your digicert config at \(configPath)")
    exit(1)
}

guard let digicertConfig = try? JSONDecoder().decode(DigicertConfig.self, from: digicertConfigData) else {
    print("Make sure the DigicertConfig is JSON with two fields, \"key\" and \"organization\"")
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

// Certified will automatically include the common name
_ = sans.filter( { $0 != commonName })
    .map({ certified.append(" +\"\($0)\"") })

try runAndPrint(bash: "/usr/bin/git checkout -b certificate-\(filename)")

sleep(1)
try runAndPrint(bash: "/usr/bin/git rm \(certPath) \(prefix)/etc/ssl/\(filename).{csr,cnf}")
try runAndPrint(bash: "/usr/bin/git rm -rf \(prefix)/etc/ssl/private/\(filename).key")
try runAndPrint(bash: "/usr/bin/git commit -a -m \"Replace certificate for \(filename)\"")

let currentDirectoryPath = manager.currentDirectoryPath
manager.changeCurrentDirectoryPath(prefix)
try runAndPrint(bash: certified)
manager.changeCurrentDirectoryPath(currentDirectoryPath)

try runAndPrint(bash: "/usr/bin/git add \(prefix)/etc/ssl/\(filename).{csr,cnf}")
try runAndPrint(bash: "/usr/bin/git commit -a -m \"New key for \(commonName)\"")

guard let csrData = manager.contents(atPath: "\(prefix)/etc/ssl/\(filename).csr"), let csr = String(bytes: csrData, encoding: .utf8) else {
    print("Could not read the generated CSR \(prefix)/etc/ssl/\(filename).csr")
    exit(1)
}

let digicert = DigicertSwift(apiKey: digicertConfig.key)
if let response = try digicert.requestCloud(commonName: commonName, sans: sans, csr: csr, organizationId: digicertConfig.organization)?.requests.first {
    print("Please visit the following URL to review and approve the request in state: \(response.status)")
    print("https://www.digicert.com/secure/requests/?status=pending#\(response.id)")
}

try runAndPrint(bash: "/usr/bin/git push origin certificate-\(filename)")
