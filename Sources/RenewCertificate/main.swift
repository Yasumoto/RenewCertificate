import Foundation
import Menkyo
import SwiftShell

var args = CommandLine.arguments

if (args.contains("--help") || args.contains("-h")) {
    print("RenewCertificate <path>.crt")
    print("Built from https://github.com/Yasumoto/RenewCertificate")
    exit(1)
}

guard args.count == 2, let path = args.last else {
    print("Please pass the path to a certificate file to renew!")
    exit(1)
}

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

var commandLine = "/usr/bin/certified --no-sign C=\"\(country)\" ST=\"\(state)\" L=\"\(locality)\" O=\"\(organization)\" CN=\"\(commonName)\""

for san in sans {
    commandLine.append(" +\"\(san)\"")
}

print(commandLine)

let output = run(bash: commandLine)
print(output.stderror)
print(output.stdout)
